// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  AgentRegistry
/// @notice DoloX protocol-level agent identity registry.
///         Tracks all Signal / Execution / Hybrid agents deployed through DoloX.
///         ERC-8004 registration is handled separately by the deployer EOA —
///         this contract is the source of truth for the DoloX A2A runtime loop.
contract AgentRegistry is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AgentAlreadyRegistered(address account);
    error AgentNotRegistered(address account);
    error ZeroAddress();
    error EmptyENSName();
    error UnauthorizedCaller(address caller);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgentRegistered(
        address indexed account,
        uint256 indexed agentId,
        string ensName,
        AgentType agentType,
        address indexed registeredBy
    );
    event AgentDeactivated(address indexed account, uint256 indexed agentId);
    event AgentReactivated(address indexed account, uint256 indexed agentId);
    event AgentEnsUpdated(address indexed account, string newEnsName);
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum AgentType {
        SIGNAL,
        EXECUTION,
        HYBRID
    }

    struct Agent {
        uint256 agentId;
        address account; // DoloXAccount (ERC-4337 smart account)
        address owner; // EOA that registered this agent
        string ensName; // e.g. "signal-dolox.base.eth"
        AgentType agentType;
        bool active;
        uint256 registeredAt;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable erc8004Registry;
    uint256 private _nextAgentId;

    mapping(address => Agent) public agents; // account → Agent
    mapping(uint256 => address) public agentIdToAccount; // agentId → account
    mapping(string => address) public ensNameToAccount; // ensName → account
    mapping(address => address[]) public ownerAgents; // owner EOA → agent accounts
    mapping(address => bool) public authorizedCallers;

    uint256 public totalAgents;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _erc8004Registry, address _owner) Ownable(_owner) {
        if (_erc8004Registry == address(0)) revert ZeroAddress();
        erc8004Registry = _erc8004Registry;
        _nextAgentId = 1;
        authorizedCallers[_owner] = true;
        emit AuthorizedCallerAdded(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a DoloX agent. Called by RegisterAgent.s.sol via authorized EOA.
    /// @param  account   DoloXAccount smart account address
    /// @param  ensName   Full Basename e.g. "signal-dolox.base.eth"
    /// @param  agentType SIGNAL(0) | EXECUTION(1) | HYBRID(2)
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

        emit AgentRegistered(account, agentId, ensName, agentType, msg.sender);
    }

    /// @notice Deactivate an agent. Only the agent's owner EOA.
    function deactivateAgent(address account) external {
        Agent storage agent = agents[account];
        if (agent.registeredAt == 0) revert AgentNotRegistered(account);
        if (agent.owner != msg.sender) revert UnauthorizedCaller(msg.sender);
        agent.active = false;
        emit AgentDeactivated(account, agent.agentId);
    }

    /// @notice Reactivate a deactivated agent. Only the agent's owner EOA.
    function reactivateAgent(address account) external {
        Agent storage agent = agents[account];
        if (agent.registeredAt == 0) revert AgentNotRegistered(account);
        if (agent.owner != msg.sender) revert UnauthorizedCaller(msg.sender);
        agent.active = true;
        emit AgentReactivated(account, agent.agentId);
    }

    /// @notice Update Basename of an agent. Only the agent's owner EOA.
    function updateEnsName(address account, string calldata newEnsName) external {
        Agent storage agent = agents[account];
        if (agent.registeredAt == 0) revert AgentNotRegistered(account);
        if (agent.owner != msg.sender) revert UnauthorizedCaller(msg.sender);
        if (bytes(newEnsName).length == 0) revert EmptyENSName();
        if (ensNameToAccount[newEnsName] != address(0)) revert AgentAlreadyRegistered(ensNameToAccount[newEnsName]);

        delete ensNameToAccount[agent.ensName];
        ensNameToAccount[newEnsName] = account;
        agent.ensName = newEnsName;
        emit AgentEnsUpdated(account, newEnsName);
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize an EOA or script to call registerAgent.
    ///         Called in Deploy.s.sol _wirePermissions to authorize deployer.
    function addAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
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

    function getOwnerAgents(address _owner) external view returns (address[] memory) {
        return ownerAgents[_owner];
    }

    function resolveEnsToAccount(string calldata ensName) external view returns (address) {
        return ensNameToAccount[ensName];
    }

    function getAgentByEns(string calldata ensName) external view returns (Agent memory) {
        address account = ensNameToAccount[ensName];
        if (account == address(0)) revert AgentNotRegistered(address(0));
        return agents[account];
    }

    function getAgentById(uint256 agentId) external view returns (Agent memory) {
        address account = agentIdToAccount[agentId];
        if (account == address(0)) revert AgentNotRegistered(address(0));
        return agents[account];
    }
}
