// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// forge script script/DeployPool.s.sol \
///     --rpc-url base_sepolia --account <keystore> --broadcast -vvvv
contract DeployPool is Script {
    address constant UNISWAP_V3_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant POSITION_MANAGER = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    uint24 constant POOL_FEE = 3000;

    uint256 constant WETH_SEED = 0.1 ether;
    uint256 constant USDC_SEED = 2000 * 1e6; // 2000 USDC (6 decimals)

    // Correct sqrtPriceX96 — verified mathematically
    // WETH=token0 (0x4200...), MockUSDC=token1 (0x4C08...)
    // Target: 1 ETH = 4000 USDC
    // raw price = 4000e6 / 1e18 = 4e-9
    // sqrtPriceX96 = sqrt(4e-9) * 2^96
    uint160 constant SQRT_PRICE_WETH_IS_TOKEN0 = 5010828967500959000000000;
    uint160 constant SQRT_PRICE_USDC_IS_TOKEN0 = 1252707241875239600000000000000000;

    // Tick for price 4e-9 ≈ -193379 — use wider safe range
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast(deployer);

        // Step 1: Deploy MockUSDC
        MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6, deployer);
        console2.log("\n[1] MockUSDC deployed:", address(mockUsdc));

        // Step 2: Mint USDC to deployer (free)
        mockUsdc.mint(deployer, USDC_SEED);
        console2.log("[2] Minted", USDC_SEED, "MockUSDC to deployer");

        // Step 3: Wrap ETH → WETH
        IWETH(WETH).deposit{value: WETH_SEED}();
        console2.log("[3] Wrapped 0.1 ETH -> WETH");

        // Step 4: Create pool
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address pool = factory.getPool(WETH, address(mockUsdc), POOL_FEE);

        if (pool == address(0)) {
            pool = factory.createPool(WETH, address(mockUsdc), POOL_FEE);
            console2.log("\n[4] Pool created:", pool);
        } else {
            console2.log("\n[4] Pool already exists:", pool);
        }

        // Step 5: Resolve token ordering FIRST, then initialize with correct sqrtPrice
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        bool wethIsToken0 = (token0 == WETH);

        console2.log("[5] token0:", token0);
        console2.log("    token1:", token1);
        console2.log("    WETH isToken0:", wethIsToken0);

        (uint160 currentSqrt,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (currentSqrt == 0) {
            // Pick sqrtPrice based on actual token order
            uint160 sqrtPrice = wethIsToken0
                ? SQRT_PRICE_WETH_IS_TOKEN0  // 5006730247845144
                : SQRT_PRICE_USDC_IS_TOKEN0; // 395825589462613675480
            IUniswapV3Pool(pool).initialize(sqrtPrice);
            console2.log("[6] Pool initialized at 1 ETH = 4000 USDC");
        } else {
            console2.log("[6] Pool already initialized");
        }

        // Step 6: Approve PositionManager
        IWETH(WETH).approve(POSITION_MANAGER, WETH_SEED);
        mockUsdc.approve(POSITION_MANAGER, USDC_SEED);
        console2.log("[7] Approvals set");

        // Step 7: Seed — respect token0/token1 order
        uint256 amount0Desired = wethIsToken0 ? WETH_SEED : USDC_SEED;
        uint256 amount1Desired = wethIsToken0 ? USDC_SEED : WETH_SEED;

        // Step 8: Add full-range liquidity
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(
                POSITION_MANAGER
            )
            .mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: POOL_FEE,
                    tickLower: TICK_LOWER,
                    tickUpper: TICK_UPPER,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: deployer,
                    deadline: block.timestamp + 600
                })
            );

        vm.stopBroadcast();

        console2.log("\n Pool Deployed & Seeded");
        console2.log("  MockUSDC:    ", address(mockUsdc));
        console2.log("  Pool:        ", pool);
        console2.log("  tokenId:     ", tokenId);
        console2.log("  Liquidity:   ", uint256(liquidity));
        console2.log("  amount0 used:", amount0, wethIsToken0 ? "(WETH)" : "(USDC)");
        console2.log("  amount1 used:", amount1, wethIsToken0 ? "(USDC)" : "(WETH)");
        console2.log("\n  Add to .env:");
        console2.log("     DOLOX_POOL=", pool);
        console2.log("     USDC=", address(mockUsdc));
    }
}
