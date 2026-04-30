// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DoloXAccountFactory} from "../src/core/DoloXAccountFactory.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {ReputationManager} from "../src/registry/ReputationManager.sol";
import {SubnameIssuer} from "../src/ens/SubnameIssuer.sol";
import {DoloXAccount} from "../src/core/DoloXAccount.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RegisterAgent is Script {
    using stdJson for string;

    /*//////////////////////////////////////////////////////////////
                              AGENT CONFIG
    //////////////////////////////////////////////////////////////*/
    // Edit these before running for each agent
    string constant SIGNAL_AGENT_NAME = "signal-dolox"; // -> signal-dolox.base.eth
    string constant EXEC_AGENT_NAME = "exec-dolox"; // -> exec-dolox.base.eth

    string constant SIGNAL_ENDPOINT = "http://localhost:3001/v1/price";
    string constant EXEC_ENDPOINT = "http://localhost:3002/v1/status";

    uint256 constant SIGNAL_AGENT_SALT = 1;
    uint256 constant EXEC_AGENT_SALT = 2;

    /*//////////////////////////////////////////////////////////////
                              LOAD DEPLOYED
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
                                  RUN
    //////////////////////////////////////////////////////////////*/
    function run() external {
        (
            DoloXAccountFactory factory,
            AgentRegistry registry,
            ReputationManager reputation,
            SubnameIssuer subnameIssuer
        ) = _loadDeployment();

        address deployer = msg.sender;

        vm.startBroadcast(deployer);

        // ── Register Signal Agent ──────────────────────────────
        console2.log("\n Registering Signal Agent");
        (address signalAccount, uint256 signalId) = _registerAgent(
            factory,
            registry,
            reputation,
            subnameIssuer,
            SIGNAL_AGENT_NAME,
            SIGNAL_ENDPOINT,
            AgentRegistry.AgentType.SIGNAL,
            SIGNAL_AGENT_SALT,
            deployer,
            "true", // canSwap
            "0" // maxSlippage (signal agent doesn't swap)
        );

        // ── Register Execution Agent ───────────────────────────
        console2.log("\n Registering Execution Agent");
        (address execAccount, uint256 execId) = _registerAgent(
            factory,
            registry,
            reputation,
            subnameIssuer,
            EXEC_AGENT_NAME,
            EXEC_ENDPOINT,
            AgentRegistry.AgentType.EXECUTION,
            EXEC_AGENT_SALT,
            deployer,
            "true", // canSwap
            "0.5" // maxSlippage
        );

        vm.stopBroadcast();

        // ── Log Results ────────────────────────────────────────
        console2.log("\n======= Agents Registered =======");
        console2.log("Signal Agent");
        console2.log("  Account:   ", signalAccount);
        console2.log("  Basename:  ", string(abi.encodePacked(SIGNAL_AGENT_NAME, ".base.eth")));
        console2.log("  ERC-8004 ID:", signalId);
        console2.log("Execution Agent");
        console2.log("  Account:   ", execAccount);
        console2.log("  Basename:  ", string(abi.encodePacked(EXEC_AGENT_NAME, ".base.eth")));
        console2.log("  ERC-8004 ID:", execId);
        console2.log("=================================\n");
    }

    /*//////////////////////////////////////////////////////////////
                         REGISTRATION FLOW
    //////////////////////////////////////////////////////////////*/

    /// @notice Full agent registration:
    ///         1. Deploy ERC-4337 smart account via factory
    ///         2. Register on AgentRegistry (ERC-8004)
    ///         3. Register Basename + write capability text records
    ///         4. Initialize reputation score
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
        // Step 1: Deploy ERC-4337 smart account (or get existing)
        account = address(factory.createAccount(deployer, salt));
        console2.log("DoloXAccount deployed:", account);

        // Step 2: Register on AgentRegistry (writes to ERC-8004)
        string memory fullName = string(abi.encodePacked(name, ".base.eth"));
        agentId = registry.registerAgent(account, fullName, agentType);
        console2.log("Registered on AgentRegistry - ERC-8004 ID:", agentId);

        // Step 3: Get Basename registration price
        uint256 price = subnameIssuer.getRegistrationPrice(name);
        console2.log("Basename price (wei):", price);

        // Step 4: Register Basename + write capability text records
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
        console2.log("Basename registered:", fullName);

        // Step 5: Initialize reputation score (starts at 100)
        reputation.initializeAgent(account);
        console2.log("Reputation initialized - starting score: 100");
    }

    function _agentTypeToString(AgentRegistry.AgentType agentType) internal pure returns (string memory) {
        if (agentType == AgentRegistry.AgentType.SIGNAL) return "SIGNAL";
        if (agentType == AgentRegistry.AgentType.EXECUTION) return "EXECUTION";
        return "HYBRID";
    }
}
