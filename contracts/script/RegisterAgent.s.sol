// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DoloXAccountFactory} from "../src/core/DoloXAccountFactory.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {ReputationManager} from "../src/registry/ReputationManager.sol";
import {SubnameIssuer} from "../src/ens/SubnameIssuer.sol";
import {stdJson} from "forge-std/StdJson.sol";

/*//////////////////////////////////////////////////////////////
                        SHARED BASE
//////////////////////////////////////////////////////////////*/

/// @notice Shared deployment loader + registration logic
///         Inherited by both RegisterSignalAgent and RegisterExecAgent
abstract contract RegisterAgentBase is Script {
    using stdJson for string;

    /*//////////////////////////////////////////////////////////////
                          LOAD DEPLOYED ADDRESSES
    //////////////////////////////////////////////////////////////*/
    function _loadDeployment()
        internal
        view
        returns (
            DoloXAccountFactory factory,
            AgentRegistry registry,
            ReputationManager reputation,
            SubnameIssuer subnameIssuer
        )
    {
        string memory path = string(abi.encodePacked("deployments/", vm.toString(block.chainid), ".json"));
        string memory json = vm.readFile(path);

        factory = DoloXAccountFactory(json.readAddress(".DoloXAccountFactory"));
        registry = AgentRegistry(json.readAddress(".AgentRegistry"));
        reputation = ReputationManager(json.readAddress(".ReputationManager"));
        subnameIssuer = SubnameIssuer(payable(json.readAddress(".SubnameIssuer")));
    }

    /*//////////////////////////////////////////////////////////////
                        CORE REGISTRATION FLOW
    //////////////////////////////////////////////////////////////*/

    /// @notice Full agent registration:
    ///         1. Deploy ERC-4337 smart account via CREATE2 factory
    ///         2. Register on AgentRegistry (ERC-8004)
    ///         3. Register Basename + write capability text records
    ///         4. Initialize reputation score (starts at 100)
    function _registerAgent(
        DoloXAccountFactory factory,
        AgentRegistry registry,
        ReputationManager reputation,
        SubnameIssuer subnameIssuer,
        string memory name,
        string memory endpoint,
        AgentRegistry.AgentType agentType,
        uint256 salt,
        address deployer,
        string memory canSwap,
        string memory maxSlippage
    ) internal returns (address account, uint256 agentId) {
        // Step 1: Deploy ERC-4337 smart account (idempotent via CREATE2)
        account = address(factory.createAccount(deployer, salt));
        console2.log("  DoloXAccount deployed:", account);

        // Step 2: Register on AgentRegistry (writes ERC-8004 identity)
        string memory fullName = string(abi.encodePacked(name, ".base.eth"));
        agentId = registry.registerAgent(account, fullName, agentType);
        console2.log("  AgentRegistry ID:", agentId);

        // Step 3: Get Basename registration price + register
        uint256 price = subnameIssuer.getRegistrationPrice(name);
        console2.log("  Basename price (wei):", price);

        subnameIssuer.registerAgentName{value: price}(
            name,
            account,
            SubnameIssuer.AgentCapabilities({
                endpoint: endpoint,
                erc8004Id: vm.toString(agentId),
                canSwap: canSwap,
                maxSlippage: maxSlippage,
                paymentToken: "USDC",
                pricePerCall: "0.001",
                agentType: _agentTypeToString(agentType)
            })
        );
        console2.log("  Basename registered:", fullName);

        // Step 4: Initialize reputation (100 base score)
        reputation.initializeAgent(account);
        console2.log("  Reputation initialized: 100");
    }

    function _agentTypeToString(AgentRegistry.AgentType agentType) internal pure returns (string memory) {
        if (agentType == AgentRegistry.AgentType.SIGNAL) return "SIGNAL";
        if (agentType == AgentRegistry.AgentType.EXECUTION) return "EXECUTION";
        return "HYBRID";
    }
}

/*//////////////////////////////////////////////////////////////
                   CONTRACT 1: SIGNAL AGENT
    forge script script/RegisterAgent.s.sol:RegisterSignalAgent \
        --rpc-url base_sepolia --account <keystore> --broadcast
//////////////////////////////////////////////////////////////*/
contract RegisterSignalAgent is RegisterAgentBase {
    string constant SIGNAL_NAME = "dolox-signal"; // → dolox-signal.base.eth
    uint256 constant SIGNAL_SALT = 1;

    function run() external {
        (
            DoloXAccountFactory factory,
            AgentRegistry registry,
            ReputationManager reputation,
            SubnameIssuer subnameIssuer
        ) = _loadDeployment();

        // -- Read endpoint from env — no hardcoded URLs --------
        string memory endpoint = vm.envString("SIGNAL_ENDPOINT");
        string memory priceEndpoint = string(abi.encodePacked(endpoint, "/price"));

        address deployer = msg.sender;

        console2.log("\n-- Registering Signal Agent --");
        console2.log("  Endpoint (from env):", priceEndpoint);

        vm.startBroadcast(deployer);

        (address account, uint256 agentId) = _registerAgent(
            factory,
            registry,
            reputation,
            subnameIssuer,
            SIGNAL_NAME,
            priceEndpoint,
            AgentRegistry.AgentType.SIGNAL,
            SIGNAL_SALT,
            deployer,
            "false", // canSwap: signal agent observes, doesn't swap
            "0" // maxSlippage: not applicable
        );

        vm.stopBroadcast();

        // -- Write to env hint ----------------------------------
        console2.log("\n======= Signal Agent Registered =======");
        console2.log("  Account:    ", account);
        console2.log("  Basename:    dolox-signal.base.eth");
        console2.log("  ERC-8004 ID:", agentId);
        console2.log("  Endpoint:   ", priceEndpoint);
        console2.log("  Add to .env:");
        console2.log("    SIGNAL_AGENT_ACCOUNT=", account);
        console2.log("=======================================\n");
    }
}

/*//////////////////////////////////////////////////////////////
                  CONTRACT 2: EXECUTION AGENT
    forge script script/RegisterAgent.s.sol:RegisterExecAgent \
        --rpc-url base_sepolia --account <keystore> --broadcast
//////////////////////////////////////////////////////////////*/
contract RegisterExecAgent is RegisterAgentBase {
    string constant EXEC_NAME = "dolox-exec"; // → dolox-exec.base.eth
    uint256 constant EXEC_SALT = 2;

    function run() external {
        (
            DoloXAccountFactory factory,
            AgentRegistry registry,
            ReputationManager reputation,
            SubnameIssuer subnameIssuer
        ) = _loadDeployment();

        // -- Read endpoint from env — no hardcoded URLs --------─
        string memory endpoint = vm.envString("EXEC_ENDPOINT");
        string memory statusEndpoint = string(abi.encodePacked(endpoint, "/status"));

        address deployer = msg.sender;

        console2.log("\n-- Registering Execution Agent --");
        console2.log("  Endpoint (from env):", statusEndpoint);

        vm.startBroadcast(deployer);

        (address account, uint256 agentId) = _registerAgent(
            factory,
            registry,
            reputation,
            subnameIssuer,
            EXEC_NAME,
            statusEndpoint,
            AgentRegistry.AgentType.EXECUTION,
            EXEC_SALT,
            deployer,
            "true", // canSwap: execution agent swaps
            "0.5" // maxSlippage: 0.5%
        );

        vm.stopBroadcast();

        // -- Write to env hint ----------------------------------─
        console2.log("\n======= Execution Agent Registered =======");
        console2.log("  Account:    ", account);
        console2.log("  Basename:    dolox-exec.base.eth");
        console2.log("  ERC-8004 ID:", agentId);
        console2.log("  Endpoint:   ", statusEndpoint);
        console2.log("  Add to .env:");
        console2.log("    EXEC_AGENT_ACCOUNT=", account);
        console2.log("==========================================\n");
    }
}
