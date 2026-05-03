# DoloX Keeper

TypeScript agent runtime that runs both the Signal Agent and Execution Agent for the DoloX protocol.

## Agents

### Signal Agent (`dolox-signal.base.eth`)

- HTTP server on `localhost:3001`
- `/v1/price` — x402-gated endpoint, returns ETH/USDC price signal
- `/v1/signal` — public endpoint, returns latest signal (for frontend)
- `/health` — public health check
- Derives price from Uniswap V3 TWAP + Uniswap Trading API
- Records `SIGNAL_FULFILLED` reputation on-chain after each paid request

### Execution Agent (`dolox-exec.base.eth`)

- Resolves `dolox-signal.base.eth` via Basenames → reads endpoint text record
- Pays 0.001 USDC per signal via x402
- Submits ERC-4337 UserOperation to Pimlico bundler
- Calls `SwapExecutor.executeSwap()` → Uniswap V3 WETH → USDC swap

## Setup

```bash
cd keeper
npm install
cp .env.example .env
# Fill in all env vars
npm run dev
```

## Environment Variables

```bash
BASE_SEPOLIA_RPC_URL=        # Alchemy or public Base Sepolia RPC
BUNDLER_URL=                 # Pimlico bundler URL for Base Sepolia
EXEC_AGENT_OWNER_PRIVATE_KEY= # EOA private key that owns exec agent
SIGNAL_OWNER_PRIVATE_KEY=    # EOA private key that owns signal agent                # Uniswap V3 pool address
UNISWAP_API_KEY=             # Uniswap Trading API key

```

## Stack

- TypeScript + Node.js
- viem — on-chain reads, Basenames resolution, ERC-4337 UserOp signing
- Pimlico bundler — `eth_sendUserOperation` JSON-RPC (v0.7)
- x402 — HTTP payment middleware + client
- Express — signal agent HTTP server
- cors — browser-accessible signal endpoint
