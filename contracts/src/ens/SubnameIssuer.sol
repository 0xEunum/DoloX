// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SubnameIssuer
/// @notice Registers DoloX agents as *.base.eth names on Base Sepolia
///         using the official Basenames contracts (ENS-compatible fork).
///
///         Basenames = ENS infrastructure deployed natively on Base.
///         Fully compatible with viem, ethers.js, ensjs out of the box.

interface IBasenamesRegistrarController {
    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
    }
    function register(RegisterRequest calldata request) external payable;
    function rentPrice(string calldata name, uint256 duration) external view returns (uint256 price);
}

interface IBasenamesL2Resolver {
    function setAddr(bytes32 node, address addr) external;
    function addr(bytes32 node) external view returns (address);
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function text(bytes32 node, string calldata key) external view returns (string memory);
}

contract SubnameIssuer is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error NameAlreadyIssued(string name);
    error EmptyName();
    error NotAuthorized();
    error InsufficientFunds(uint256 required, uint256 provided);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgentNameRegistered(address indexed account, string name, string fullName, bytes32 indexed node);
    event CapabilityRecordSet(address indexed account, string key, string value);
    event AuthorizedIssuerAdded(address indexed issuer);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Machine-readable capability manifest stored in text records
    /// @dev Enables exec agents to discover signal agents via ENS text records
    ///      WITHOUT hardcoded endpoints — pure ENS-native service discovery
    struct AgentCapabilities {
        string endpoint; // x402 payment endpoint URL
        string erc8004Id; // ERC-8004 agent registry ID
        string canSwap; // "true" / "false"
        string maxSlippage; // e.g., "0.5"
        string paymentToken; // "USDC"
        string pricePerCall; // e.g., "0.001"
        string agentType; // "SIGNAL" / "EXECUTION" / "HYBRID"
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IBasenamesRegistrarController public immutable registrarController;
    IBasenamesL2Resolver public immutable l2Resolver;

    // dolox.base.eth namehash — precomputed off-chain, set in constructor
    // namehash("dolox.base.eth")
    bytes32 public immutable doloxBaseNode;

    uint256 public constant REGISTRATION_DURATION = 365 days;

    // name (without .base.eth) => issued
    mapping(string => bool) public issuedNames;

    // account => basename node
    mapping(address => bytes32) public accountToNode;

    // account => full name e.g., "dolox-signal.base.eth"
    mapping(address => string) public accountToName;

    // authorized callers (AgentRegistry)
    mapping(address => bool) public authorizedIssuers;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _registrarController, address _l2Resolver, bytes32 _doloxBaseNode, address _owner)
        Ownable(_owner)
    {
        if (_registrarController == address(0) || _l2Resolver == address(0)) {
            revert ZeroAddress();
        }
        registrarController = IBasenamesRegistrarController(_registrarController);
        l2Resolver = IBasenamesL2Resolver(_l2Resolver);
        doloxBaseNode = _doloxBaseNode;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorized() {
        if (!authorizedIssuers[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a *.base.eth name for a DoloX agent
    /// @param name e.g., "dolox-signal" → dolox-signal.base.eth
    /// @param account The DoloXAccount address
    /// @param capabilities Agent capability manifest written as text records
    function registerAgentName(string calldata name, address account, AgentCapabilities calldata capabilities)
        external
        payable
        onlyAuthorized
        returns (bytes32 node)
    {
        if (account == address(0)) revert ZeroAddress();
        if (bytes(name).length == 0) revert EmptyName();
        if (issuedNames[name]) revert NameAlreadyIssued(name);

        // Check registration price
        uint256 price = registrarController.rentPrice(name, REGISTRATION_DURATION);
        if (msg.value < price) revert InsufficientFunds(price, msg.value);

        // Compute namehash for this registered name
        node = keccak256(abi.encodePacked(doloxBaseNode, keccak256(bytes(name))));

        // Register with SubnameIssuer as ENS owner
        registrarController.register{value: price}(
            IBasenamesRegistrarController.RegisterRequest({
                name: name,
                owner: address(this),
                duration: REGISTRATION_DURATION,
                resolver: address(l2Resolver),
                data: new bytes[](0),
                reverseRecord: false
            })
        );

        // SubnameIssuer is now the ENS owner -> authorized to call setText + setAddr
        // Point addr() to agent's DoloXAccount (what viem resolves)
        l2Resolver.setAddr(node, account);

        // Write all 7 capability text records
        l2Resolver.setText(node, "endpoint", capabilities.endpoint);
        l2Resolver.setText(node, "erc8004Id", capabilities.erc8004Id);
        l2Resolver.setText(node, "canSwap", capabilities.canSwap);
        l2Resolver.setText(node, "maxSlippage", capabilities.maxSlippage);
        l2Resolver.setText(node, "paymentToken", capabilities.paymentToken);
        l2Resolver.setText(node, "pricePerCall", capabilities.pricePerCall);
        l2Resolver.setText(node, "agentType", capabilities.agentType);

        issuedNames[name] = true;
        accountToNode[account] = node;
        accountToName[account] = string(abi.encodePacked(name, ".base.eth"));

        emit AgentNameRegistered(account, name, string(abi.encodePacked(name, ".base.eth")), node);

        if (msg.value > price) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - price}("");
            (ok);
        }
    }

    /// @notice Update a single capability text record for an agent
    function updateCapability(address account, string calldata key, string calldata value) external onlyAuthorized {
        bytes32 node = accountToNode[account];
        l2Resolver.setText(node, key, value);
        emit CapabilityRecordSet(account, key, value);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN
    //////////////////////////////////////////////////////////////*/
    function addAuthorizedIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = true;
        emit AuthorizedIssuerAdded(issuer);
    }

    function withdraw() external onlyOwner {
        (bool ok,) = payable(owner()).call{value: address(this).balance}("");
        (ok);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/
    function getAgentName(address account) external view returns (string memory) {
        return accountToName[account];
    }

    function getAgentNode(address account) external view returns (bytes32) {
        return accountToNode[account];
    }

    function getRegistrationPrice(string calldata name) external view returns (uint256) {
        return registrarController.rentPrice(name, REGISTRATION_DURATION);
    }

    receive() external payable {}
}
