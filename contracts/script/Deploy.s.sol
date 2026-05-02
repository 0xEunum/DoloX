// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DoloXAccountFactory} from "../src/core/DoloXAccountFactory.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {ReputationManager} from "../src/registry/ReputationManager.sol";
import {SubnameIssuer} from "../src/ens/SubnameIssuer.sol";
import {SwapExecutor} from "../src/execution/SwapExecutor.sol";
import {PaymentVerifier} from "../src/execution/PaymentVerifier.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockBasenamesController} from "../src/mocks/MockBasenamesController.sol";
import {MockBasenamesResolver} from "../src/mocks/MockBasenamesResolver.sol";
import {MockERC8004Registry} from "../src/mocks/MockERC8004Registry.sol";
import {MockEntryPoint} from "../src/mocks/MockEntryPoint.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract Deploy is Script {
    using stdJson for string;

    /*//////////////////////////////////////////////////////////////
                           DEPLOYED CONTRACTS
    //////////////////////////////////////////////////////////////*/
    DoloXAccountFactory public factory;
    AgentRegistry public registry;
    ReputationManager public reputation;
    SubnameIssuer public subnameIssuer;
    SwapExecutor public swapExecutor;
    PaymentVerifier public paymentVerifier;

    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig public config;

    /*//////////////////////////////////////////////////////////////
                               DEPLOY
    //////////////////////////////////////////////////////////////*/
    function run()
        external
        returns (
            DoloXAccountFactory,
            AgentRegistry,
            ReputationManager,
            SubnameIssuer,
            SwapExecutor,
            PaymentVerifier,
            HelperConfig
        )
    {
        helperConfig = new HelperConfig();

        address deployer = msg.sender;

        vm.startBroadcast(deployer);

        // On Anvil: deploy mocks first, then update config
        if (block.chainid == helperConfig.ANVIL_CHAIN_ID()) {
            _deployAnvilMocks(deployer);
        }

        config = helperConfig.getNetworkConfig();

        _deployCore();
        _deployRegistry(deployer);
        _deployENS(deployer);
        _deployExecution();
        _wirePermissions(deployer);

        vm.stopBroadcast();

        _saveDeployment();
        _logDeployment();

        return (factory, registry, reputation, subnameIssuer, swapExecutor, paymentVerifier, helperConfig);
    }

    /*//////////////////////////////////////////////////////////////
                        ANVIL MOCK DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Deploys all mock external contracts on Anvil
    ///      Runs INSIDE vm.startBroadcast — same sender as everything else
    function _deployAnvilMocks(address deployer) internal {
        MockEntryPoint mockEntryPoint = new MockEntryPoint();
        MockBasenamesController mockController = new MockBasenamesController();
        MockBasenamesResolver mockResolver = new MockBasenamesResolver();
        MockERC8004Registry mockERC8004 = new MockERC8004Registry();
        MockERC20 mockWeth = new MockERC20("Mock WETH", "mWETH", 18, deployer);
        MockERC20 mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6, deployer);

        console2.log("MockBasenamesController:", address(mockController));
        console2.log("MockBasenamesResolver:  ", address(mockResolver));
        console2.log("MockERC8004Registry:    ", address(mockERC8004));
        console2.log("MockWETH:               ", address(mockWeth));
        console2.log("MockUSDC:               ", address(mockUsdc));

        // Push mock addresses back into HelperConfig
        helperConfig.setAnvilMocks(
            address(mockEntryPoint),
            address(mockERC8004),
            address(mockController),
            address(mockResolver),
            address(mockWeth),
            address(mockUsdc)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOY STEPS
    //////////////////////////////////////////////////////////////*/

    /// @dev Step 1 — ERC-4337 account factory
    function _deployCore() internal {
        factory = new DoloXAccountFactory(config.entryPoint);
        console2.log("DoloXAccountFactory:", address(factory));
    }

    /// @dev Step 2 — ERC-8004 agent registry + reputation
    function _deployRegistry(address deployer) internal {
        registry = new AgentRegistry(config.erc8004Registry, deployer);
        console2.log("AgentRegistry:", address(registry));

        reputation = new ReputationManager(address(registry), deployer);
        console2.log("ReputationManager:", address(reputation));
    }

    /// @dev Step 3 — Basenames subname issuer
    function _deployENS(address deployer) internal {
        // dolox.base.eth namehash — precomputed
        // namehash("base.eth") = 0xff1e3c0eb00ec714e34b6114125fbde1dea2f24a72e7f479de07fd7470ad7b3f
        // This is used as parent node for *.base.eth registrations
        bytes32 doloxBaseNode = 0x646204f07e7fcd394a508306bf1148a1e13d14287fa33839bf9ad63755f547c6;

        subnameIssuer = new SubnameIssuer(config.basenamesController, config.basenamesResolver, doloxBaseNode, deployer);
        console2.log("SubnameIssuer:", address(subnameIssuer));
    }

    /// @dev Step 4 — Swap execution + x402 payment verification
    function _deployExecution() internal {
        // On Anvil, swapRouter is address(0) — swap execution skipped in tests
        address router = config.swapRouter == address(0)
            ? address(1)  // placeholder for Anvil — tests mock swap calls
            : config.swapRouter;

        swapExecutor = new SwapExecutor(router, address(registry), address(reputation));
        console2.log("SwapExecutor:", address(swapExecutor));

        paymentVerifier = new PaymentVerifier(address(registry), address(reputation));
        console2.log("PaymentVerifier:", address(paymentVerifier));
    }

    /// @dev Step 5 — Wire all permissions between contracts
    function _wirePermissions(address deployer) internal {
        // ReputationManager: authorize SwapExecutor + PaymentVerifier to record events
        reputation.addAuthorizedCaller(address(swapExecutor));
        reputation.addAuthorizedCaller(address(paymentVerifier));
        console2.log("ReputationManager: authorized SwapExecutor + PaymentVerifier");

        // SubnameIssuer: authorize deployer (used in RegisterAgent.s.sol)
        // AgentRegistry will also be authorized after deploy
        subnameIssuer.addAuthorizedIssuer(deployer);
        console2.log("SubnameIssuer: authorized deployer");

        // ReputationManager: authorize deployer for manual init
        reputation.addAuthorizedCaller(deployer);
        console2.log("ReputationManager: authorized deployer");
    }

    /*//////////////////////////////////////////////////////////////
                         SAVE + LOG
    //////////////////////////////////////////////////////////////*/
    function _saveDeployment() internal {
        string memory json = "deployment";

        vm.serializeAddress(json, "DoloXAccountFactory", address(factory));
        vm.serializeAddress(json, "AgentRegistry", address(registry));
        vm.serializeAddress(json, "ReputationManager", address(reputation));
        vm.serializeAddress(json, "SubnameIssuer", address(subnameIssuer));
        vm.serializeAddress(json, "SwapExecutor", address(swapExecutor));
        vm.serializeAddress(json, "PaymentVerifier", address(paymentVerifier));
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeUint(json, "deployedAt", block.timestamp);
        string memory output = vm.serializeAddress(json, "EntryPoint", config.entryPoint);

        string memory path = string(abi.encodePacked("deployments/", vm.toString(block.chainid), ".json"));
        vm.writeJson(output, path);
        console2.log("Deployment saved to:", path);
    }

    function _logDeployment() internal view {
        console2.log("\n======= DoloX Protocol Deployed =======");
        console2.log("Chain ID:           ", block.chainid);
        console2.log("EntryPoint:         ", config.entryPoint);
        console2.log("ERC-8004 Registry:  ", config.erc8004Registry);
        console2.log("Factory:            ", address(factory));
        console2.log("AgentRegistry:      ", address(registry));
        console2.log("ReputationManager:  ", address(reputation));
        console2.log("SubnameIssuer:      ", address(subnameIssuer));
        console2.log("SwapExecutor:       ", address(swapExecutor));
        console2.log("PaymentVerifier:    ", address(paymentVerifier));
        console2.log("========================================\n");
    }
}
