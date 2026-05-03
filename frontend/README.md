# DoloX Frontend

Read-only React dashboard for the DoloX protocol. Displays live agent status, reputation scores, swap history, and x402 payment feed — all from on-chain data via viem.

No wallet connection required.

## Features

- Live agent cards — Basename, smart account, ERC-8004 reputation score, balances
- Swap history — pulled from `SwapExecuted` on-chain events
- x402 payment feed — pulled from USDC `Transfer` events
- Current signal card — live fetch from `localhost:3001/v1/signal`
- Pool status — live WETH/USDC reserves
- Architecture diagram
- Auto-refresh every 30 seconds

## Setup

```bash
cd frontend
npm install
npm run dev     # localhost:8080
```

## Stack

- React + Vite + TypeScript
- TailwindCSS + shadcn/ui
- viem (pure public client, no wallet)
- Public Base Sepolia RPC — `https://base-sepolia-rpc.publicnode.com`

## Notes

- All contract addresses are hardcoded in `src/lib/dolox/contracts.ts`
- All amounts: WETH divides by `1e18`, USDC divides by `1e6`
- Reputation score: 0–1000, initial 100
- Frontend was scaffolded with AI assistance (Lovable) — see `ATTRIBUTION.md`
