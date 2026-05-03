# Uniswap Foundation — Integration Feedback

Project: DoloX Protocol
Track: Uniswap Foundation
Builder: Mohd Muzammil (@0xEunum)
GitHub: https://github.com/0xEunum/dolox

## What We Built

DoloX uses Uniswap V3 as the execution and settlement layer for autonomous DeFi agents. Two agents — a Signal Agent and an Execution Agent — coordinate on-chain without human intervention. The exec agent submits ERC-4337 UserOperations that call `SwapExecutor.executeSwap()`, which wraps Uniswap V3's `exactInputSingle` to execute WETH to USDC swaps on Base Sepolia.

Price signals come from two sources running in parallel:
- Uniswap V3 pool TWAP via `observe()` — 5-minute rolling average tick from the deployed Base Sepolia pool
- Uniswap Trading API (`/v1/quote`) — real-world ETH/USDC price from Base mainnet as an external reference

The signal logic compares spot price vs TWAP deviation to decide BUY / SELL / HOLD.

## Uniswap Products Used

- **Uniswap V3 SwapRouter02** — `exactInputSingle` inside `SwapExecutor.sol` for agent swap execution
- **Uniswap V3 Pool** — `slot0` for spot price, `observe([secondsAgo, 0])` for 5-min TWAP
- **Uniswap Trading API** — `/v1/quote` on Base mainnet for real-world ETH/USDC price reference
- **Uniswap V3 Factory** — deployed a fresh WETH/USDC 0.3% pool on Base Sepolia for testnet liquidity

## What Worked Well

- `exactInputSingle` on SwapRouter02 is clean to wrap in a Solidity contract — minimal surface area, straightforward integration
- `observe()` for TWAP works well once the pool has some history — the tick math (`tickCumulatives` delta / secondsAgo) is reliable
- Uniswap V3 on Base Sepolia has good RPC support — no issues with contract calls
- The Trading API `/v1/quote` endpoint was easy to call and returned fast — useful for getting a real-world price anchor on testnet

## What Was Challenging

- **Uniswap API response shape** — The `/v1/quote` endpoint response structure is not clearly documented for different routing modes. For CLASSIC routing on Base mainnet, the USDC output amount is at `data.quote.output` (a string, divide by 1e6 for USDC). Spent time iterating through `data.output`, `data.quote.outputAmount`, and `data.quote.output.amount` before landing on the correct path via console logging the full response.

- **TWAP on a fresh pool** — A newly deployed Uniswap V3 pool initializes with `observationCardinality = 1`, which means `observe()` reverts if you request a window longer than the pool's age. The error is not descriptive — it just reverts with no message. Had to add a try/catch fallback to spot price and log "Pool too fresh for TWAP" to handle this gracefully.

- **One-directional testnet signals** — On a testnet pool with only one agent swapping one direction (WETH to USDC), the spot price drifts below TWAP after every swap and never recovers. This means the signal is always BUY. On mainnet with real two-sided liquidity this is fine, but on testnet it makes the signal logic feel shallow. A counter-party or pool rebalancer would be needed for a more realistic demo.

- **No test USDC on Base Sepolia from Uniswap** — Had to deploy a MockERC20 and seed the pool manually. The testnet setup friction (deploy token, create pool, initialize price, seed liquidity) took meaningful time away from building the actual protocol.

## Suggestions for Uniswap Developer Platform

- **Document `/v1/quote` response shape per routing type** — CLASSIC, DUTCH_V2, and PRIORITY routing return different JSON structures. A clear schema per routing type in the docs would save builders significant time. Even a simple example response object per type would help.

- **Describe `observe()` revert behavior in V3 docs** — The pool reverts silently when `observationCardinality = 1` and you request a window larger than the pool age. Documenting this edge case (and the fix — call `increaseObservationCardinalityNext` after pool creation) would help devs building TWAP-based applications.

- **Maintained test tokens on Base Sepolia** — A Uniswap-maintained WETH/USDC pool with real liquidity on Base Sepolia would remove a significant setup barrier for hackathon builders. Even a faucet for test USDC on Base Sepolia would help.

## Contract Addresses (Base Sepolia)

- SwapExecutor: `0xC11499825eD583101708786825cBa8c390D4E347`
- DoloX Pool (WETH/USDC 0.3%): `0xdcD3c1239bc4F523eC2d20C22E7564477Cf5D1fA`
- Uniswap SwapRouter02 (Base Sepolia): `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4`
- Uniswap V3 Factory (Base Sepolia): `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`
