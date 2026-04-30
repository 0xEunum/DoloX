// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AgentRegistry} from "../registry/AgentRegistry.sol";
import {ReputationManager} from "../registry/ReputationManager.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title SwapExecutor
/// @notice Called by DoloXAccount (via ERC-4337 UserOp) to execute
///         Uniswap V3 swaps on behalf of registered agents.
///         Updates agent reputation after each swap attempt.
contract SwapExecutor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AgentNotRegistered(address account);
    error ZeroAmount();
    error ZeroAddress();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InvalidFee();
    error ExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SwapExecuted(
        address indexed agentAccount,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint24 fee,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ISwapRouter public immutable swapRouter;
    AgentRegistry public immutable registry;
    ReputationManager public immutable reputation;

    // Base Sepolia Uniswap V3 SwapRouter02
    // Address set via constructor from env

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _swapRouter, address _registry, address _reputation) {
        if (_swapRouter == address(0) || _registry == address(0) || _reputation == address(0)) {
            revert ZeroAddress();
        }
        swapRouter = ISwapRouter(_swapRouter);
        registry = AgentRegistry(_registry);
        reputation = ReputationManager(_reputation);
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a Uniswap V3 exactInputSingle swap on behalf of an agent
    /// @dev msg.sender must be the DoloXAccount (agent smart account)
    /// @param tokenIn  Token to sell
    /// @param tokenOut Token to buy
    /// @param fee      Pool fee tier (500, 3000, 10000)
    /// @param amountIn Exact amount of tokenIn to sell
    /// @param amountOutMinimum Minimum acceptable amountOut (slippage protection)
    function executeSwap(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMinimum)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (!registry.isRegistered(msg.sender)) revert AgentNotRegistered(msg.sender);
        if (amountIn == 0) revert ZeroAmount();
        if (fee != 500 && fee != 3000 && fee != 10000) revert InvalidFee();

        // Pull tokens from the agent's smart account (msg.sender)
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender, // tokens go back to the agent smart account
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        try swapRouter.exactInputSingle(params) returns (uint256 out) {
            amountOut = out;

            if (amountOut < amountOutMinimum) revert SlippageExceeded(amountOut, amountOutMinimum);

            // Reward agent reputation on success
            reputation.recordEvent(msg.sender, ReputationManager.ReputationEvent.SWAP_SUCCESS);

            emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, fee, block.timestamp);
        } catch {
            // Penalize agent reputation on failure
            reputation.recordEvent(msg.sender, ReputationManager.ReputationEvent.SWAP_FAILED);
            revert ExecutionFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function isAgentEligible(address account) external view returns (bool) {
        return registry.isRegistered(account);
    }
}
