// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice DoloX wrapper around ERC-8004 identity registry.
///         Registers agent smart accounts as verifiable onchain entities.
///         ERC-8004 Identity Registry on Base Sepolia:
///         0x8004A818BFB912233c491871b3d84c89A494BD9e
contract AgentRegistry is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AgentAlreadyRegistered(address account);
    error AgentNotRegistered(address account);
    error ZeroAddress();
    error EmptyENSName();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgentRegistered(address indexed account, uint256 indexed agentId, string ensName, AgentType agentType);
    event AgentDeactivated(address indexed account, uint256 indexed agentId);
    event AgentUpdated(address indexed account, string newEnsName);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum AgentType {
        SIGNAL, // Provides price signals via x402
        EXECUTION, // Executes swaps based on signals
        HYBRID // Both signal + execution
    }

    struct Agent {
        uint256 agentId; // ERC-8004 registry ID
        address account; // DoloXAccount address (ERC-4337)
        address owner; // Owner EOA
        string ensName; // e.g., "signal.dolox.eth"
        AgentType agentType;
        bool active;
        uint256 registeredAt;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // ERC-8004 external registry (Base Sepolia deployed)
    address public immutable erc8004Registry;

    uint256 private _nextAgentId;

    // account address => Agent
    mapping(address => Agent) public agents;

    // agentId => account address
    mapping(uint256 => address) public agentIdToAccount;

    // ensName => account address
    mapping(string => address) public ensNameToAccount;

    // owner => list of their agent accounts
    mapping(address => address[]) public ownerAgents;

    // total registered agents
    uint256 public totalAgents;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _erc8004Registry, address _owner) Ownable(_owner) {
        if (_erc8004Registry == address(0)) revert ZeroAddress();
        erc8004Registry = _erc8004Registry;
        _nextAgentId = 1;
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a DoloXAccount as an agent in the DoloX protocol
    /// @param account The ERC-4337 smart account address (DoloXAccount)
    /// @param ensName The ENS subname assigned to this agent (e.g. "signal.dolox.eth")
    /// @param agentType SIGNAL, EXECUTION, or HYBRID
    function registerAgent(address account, string calldata ensName, AgentType agentType)
        external
        returns (uint256 agentId)
    {
        if (account == address(0)) revert ZeroAddress();
        if (agents[account].registeredAt != 0) revert AgentAlreadyRegistered(account);
        if (bytes(ensName).length == 0) revert EmptyENSName();
        if (ensNameToAccount[ensName] != address(0)) revert AgentAlreadyRegistered(ensNameToAccount[ensName]);

        agentId = _nextAgentId++;

        agents[account] = Agent({
            agentId: agentId,
            account: account,
            owner: msg.sender,
            ensName: ensName,
            agentType: agentType,
            active: true,
            registeredAt: block.timestamp
        });

        agentIdToAccount[agentId] = account;
        ensNameToAccount[ensName] = account;
        ownerAgents[msg.sender].push(account);
        totalAgents++;

        // Interact with external ERC-8004 registry
        _registerOnERC8004(account, agentId, ensName);

        emit AgentRegistered(account, agentId, ensName, agentType);
    }

    /// @notice Deactivate an agent — owner only
    function deactivateAgent(address account) external {
        Agent storage agent = agents[account];
        if (agent.registeredAt == 0) revert AgentNotRegistered(account);
        if (agent.owner != msg.sender) revert AgentNotRegistered(account);
        agent.active = false;
        emit AgentDeactivated(account, agent.agentId);
    }

    /// @notice Update ENS name for an agent — owner only
    function updateEnsName(address account, string calldata newEnsName) external {
        Agent storage agent = agents[account];
        if (agent.registeredAt == 0) revert AgentNotRegistered(account);
        if (agent.owner != msg.sender) revert AgentNotRegistered(account);
        if (bytes(newEnsName).length == 0) revert EmptyENSName();

        // Clear old ENS mapping
        delete ensNameToAccount[agent.ensName];
        ensNameToAccount[newEnsName] = account;
        agent.ensName = newEnsName;

        emit AgentUpdated(account, newEnsName);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function getAgent(address account) external view returns (Agent memory) {
        if (agents[account].registeredAt == 0) revert AgentNotRegistered(account);
        return agents[account];
    }

    function isRegistered(address account) external view returns (bool) {
        return agents[account].registeredAt != 0 && agents[account].active;
    }

    function getOwnerAgents(address owner) external view returns (address[] memory) {
        return ownerAgents[owner];
    }

    function resolveEnsToAccount(string calldata ensName) external view returns (address) {
        return ensNameToAccount[ensName];
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Calls ERC-8004 external registry to register agent identity
    ///      Low-level call — if ERC-8004 registry reverts, we still proceed
    ///      (graceful degradation for testnet availability)
    function _registerOnERC8004(address account, uint256 agentId, string memory ensName) internal {
        bytes memory callData = abi.encodeWithSignature("register(address,uint256,string)", account, agentId, ensName);
        // Graceful — don't revert if ERC-8004 registry is unavailable on testnet
        (bool success,) = erc8004Registry.call(callData);
        (success); // suppress unused variable warning
    }
}
