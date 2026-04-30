// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockBasenamesController} from "../src/mocks/MockBasenamesController.sol";
import {MockBasenamesResolver} from "../src/mocks/MockBasenamesResolver.sol";
import {MockERC8004Registry} from "../src/mocks/MockERC8004Registry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        // ERC-4337
        address entryPoint;
        // ERC-8004
        address erc8004Registry;
        // Basenames
        address basenamesController;
        address basenamesResolver;
        // Uniswap V3
        address uniswapFactory;
        address swapRouter;
        address nonfungiblePositionManager;
        // Tokens
        address weth;
        address usdc;
        // Pool
        uint24 poolFee;
        // Chain
        uint256 chainId;
        bool isTestnet;
    }

    /*//////////////////////////////////////////////////////////////
                            CHAIN IDS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    NetworkConfig public activeConfig;

    error HelperConfig__InvalidChainId();

    constructor() {
        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            activeConfig = getBaseSepoliaConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeConfig = getOrCreateAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        BASE SEPOLIA CONFIG
    //////////////////////////////////////////////////////////////*/
    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // ERC-4337 EntryPoint v0.7
            entryPoint: 0x0000000071727De22E5E9d8BAf0edAc6f37da032,
            // ERC-8004 Identity Registry
            erc8004Registry: 0x8004A818BFB912233c491871b3d84c89A494BD9e,
            // Basenames (ENS-compatible on Base)
            basenamesController: 0x49aE3cC2e3AA768B1e5654f5D3C6002144A59581,
            basenamesResolver: 0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA,
            // Uniswap V3
            uniswapFactory: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24,
            swapRouter: 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4,
            nonfungiblePositionManager: 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2,
            // Native tokens
            weth: 0x4200000000000000000000000000000000000006,
            usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            poolFee: 3000,
            chainId: BASE_SEPOLIA_CHAIN_ID,
            isTestnet: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                          ANVIL CONFIG
    //////////////////////////////////////////////////////////////*/
    function getOrCreateAnvilConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: address(0),
            erc8004Registry: address(0),
            basenamesController: address(0),
            basenamesResolver: address(0),
            uniswapFactory: address(0),
            swapRouter: address(0),
            nonfungiblePositionManager: address(0),
            weth: address(0),
            usdc: address(0),
            poolFee: 3000,
            chainId: ANVIL_CHAIN_ID,
            isTestnet: true
        });
    }

    /// @dev Called by Deploy.s.sol after deploying mocks on Anvil
    function setAnvilMocks(
        address mockEntryPoint,
        address erc8004Registry,
        address basenamesController,
        address basenamesResolver,
        address weth,
        address usdc
    ) external {
        require(activeConfig.chainId == ANVIL_CHAIN_ID, "Only Anvil");
        activeConfig.entryPoint = mockEntryPoint;
        activeConfig.erc8004Registry = erc8004Registry;
        activeConfig.basenamesController = basenamesController;
        activeConfig.basenamesResolver = basenamesResolver;
        activeConfig.weth = weth;
        activeConfig.usdc = usdc;
    }

    function getNetworkConfig() external view returns (NetworkConfig memory) {
        return activeConfig;
    }
}
