# DoloX Protocol

> Autonomous DeFi agents with on-chain identity, capability discovery, and machine-to-machine payments.

DoloX is a permissionless protocol for spawning autonomous DeFi agents that own their funds via ERC-4337 smart accounts, are discoverable by Basenames (ENS-compatible naming on Base), pay each other for services via x402, execute swaps via Uniswap V3, and build verifiable on-chain reputation via ERC-8004.

---

## The Problem

Current DeFi automation is fragile - bots control user wallets, endpoints are hardcoded, agents have no persistent identity, and there is no standard for agent-to-agent coordination or payment. Agents cannot discover each other, cannot pay each other, and cannot prove their track record.

## The Solution

DoloX introduces a protocol where:

- **Agents own themselves** - each agent is an ERC-4337 smart account, not a bot controlling your EOA
- **Agents are discoverable** - each agent gets a Basename (`dolox-signal.base.eth`) with capabilities encoded in ENS-compatible text records
- **Agents pay each other** - x402 enables per-request micropayments between agents with no API keys or subscriptions
- **Agents earn reputation** - every fulfilled request and successful swap updates an ERC-8004 on-chain reputation score

---

## Network

**Base Sepolia Testnet**

- Chain ID: `84532`
- RPC: `https://sepolia.base.org`
- Explorer: `https://sepolia.basescan.org`

---

## Live Agents

| Agent        | Basename                | Smart Account                                |
| ------------ | ----------------------- | -------------------------------------------- |
| Signal Agent | `dolox-signal.base.eth` | `0x28be458F90A200D4A62A352B981B1ebc80dcE21D` |
| Exec Agent   | `dolox-exec.base.eth`   | `0x8CF9CbFBaD0140629Afec50ED56955072f2Cea10` |

---

## Demo

|                      |                                             |
| -------------------- | ------------------------------------------- |
| 🌐 **Live Frontend** | https://dolox-zeta.vercel.app/              |
| 🎥 **Demo Video**    | https://www.youtube.com/watch?v=yhiDvUPkSWc |

> The frontend is always live — shows real on-chain data from Base Sepolia, no wallet needed.
> Start the keeper locally (`cd keeper && npm run dev`) to see live signals and swaps execute in real time.

---

## Architecture

```
New Agent Spawned
      |
DoloXAccountFactory deploys ERC-4337 Smart Account (DoloXAccount)
      |
AgentRegistry registers agent on ERC-8004 Identity Registry
      |
SubnameIssuer registers agent on Basenames:
  dolox-signal.base.eth -> DoloXAccount address
  + writes text records: { endpoint, erc8004Id, canSwap, paymentToken, pricePerCall, agentType }
      |
Agent is LIVE - discoverable by name, capabilities readable from Basenames text records

-------- A2A RUNTIME LOOP --------

ExecAgent wakes up every 30 seconds
      |
Resolves dolox-signal.base.eth via viem -> reads x402 endpoint from text record
      |
Calls signal endpoint -> receives HTTP 402 + payment details
      |
Pays 0.001 USDC on-chain via x402 -> attaches X-PAYMENT proof header
      |
SignalAgent verifies payment -> returns price signal { action: "BUY", price: 3845.13 }
      |
ExecAgent submits ERC-4337 UserOperation -> SwapExecutor called
      |
Uniswap V3 swap executes on-chain
      |
ReputationManager updates ERC-8004 scores for both agents
      |
Frontend reflects: new swap in history, reputation scores updated, zero human clicks
```

---

## Project Structure

```
dolox/
├── contracts/
│   ├── src/
│   │   ├── core/
│   │   │   ├── DoloXAccount.sol          ERC-4337 smart account for each agent
│   │   │   ├── DoloXAccountFactory.sol   Deploys agent accounts via CREATE2
│   │   │   └── EntryPoint.sol            ERC-4337 EntryPoint interface
│   │   ├── registry/
│   │   │   ├── AgentRegistry.sol         ERC-8004 wrapper - registers agent identity
│   │   │   └── ReputationManager.sol     On-chain reputation score per agent
│   │   ├── ens/
│   │   │   └── SubnameIssuer.sol         Registers agent Basenames + writes text records
│   │   ├── execution/
│   │   │   ├── SwapExecutor.sol          Uniswap V3 swap logic called by agents
│   │   │   └── PaymentVerifier.sol       Verifies x402 payment proofs on-chain
│   │   └── mocks/
│   │       └── MockERC20.sol             Mock tokens for Uniswap pool seeding on testnet
│   ├── test/
│   │   ├── DoloXAccount.t.sol
│   │   ├── AgentRegistry.t.sol
│   │   ├── SubnameIssuer.t.sol
│   │   └── SwapExecutor.t.sol
│   └── script/
│       ├── Deploy.s.sol                  Full protocol deployment + pool seeding
│       └── RegisterAgent.s.sol          Register an agent (Basenames + ERC-8004)
│
├── keeper/
│   ├── src/
│   │   ├── agents/
│   │   │   ├── signalAgent.ts            HTTP price signal server, x402 gated
│   │   │   └── execAgent.ts              Resolves signal agent via Basenames, pays x402, swaps
│   │   ├── core/
│   │   │   ├── x402Server.ts             x402 payment middleware (verify + fulfill)
│   │   │   ├── x402Client.ts             x402 payment client (discover + pay)
│   │   │   ├── basenamesResolver.ts      Resolves *.base.eth names + reads text records via viem
│   │   │   └── erc4337.ts                UserOperation builder + bundler client (Pimlico)
│   │   ├── uniswap/
│   │   │   └── priceOracle.ts            Fetches live price from Uniswap V3 pool TWAP
│   │   └── index.ts                      Bootstraps both agents
│   └── .env.example
│
└── frontend/
    └── src/
        ├── components/
        │   ├── AgentCard.tsx             Agent Basename, status, smart account, reputation
        │   ├── SwapHistory.tsx           Uniswap swap txs pulled from on-chain events
        │   ├── PaymentFeed.tsx           Live feed of agent-to-agent x402 payments
        │   └── CurrentSignal.tsx         Live price signal from keeper localhost:3001
        └── lib/
            └── dolox/                    Contract ABIs, addresses, viem client, utils
```

---

## Standards & Protocols

| Standard       | Role in DoloX                                                                              |
| -------------- | ------------------------------------------------------------------------------------------ |
| **ERC-4337**   | Each agent is a smart account - owns funds, signs UserOps, pays its own gas                |
| **ERC-8004**   | On-chain agent identity and reputation registry - agents are verifiable entities           |
| **Basenames**  | ENS-compatible naming on Base - agents get `*.base.eth` names with capability text records |
| **x402**       | HTTP-native micropayments - exec agent pays signal agent per price request in USDC         |
| **Uniswap V3** | On-chain swap execution layer + TWAP price oracle                                          |

---

## Basenames - ENS-Compatible Identity on Base

DoloX uses **Basenames** - the official ENS-compatible naming system built natively on Base by Coinbase. Each DoloX agent receives a `*.base.eth` name at registration time carrying machine-readable **capability text records** that enable autonomous endpoint discovery - no hardcoded URLs:

```json
{
  "endpoint": "http://localhost:3001/v1",
  "erc8004Id": "1",
  "canSwap": "false",
  "paymentToken": "USDC",
  "pricePerCall": "0.001",
  "agentType": "SIGNAL",
  "version": "1.0.0",
  "protocol": "dolox"
}
```

ExecAgent resolves `dolox-signal.base.eth` -> reads `endpoint` text record -> calls it via x402. No config files. No hardcoded URLs. Pure ENS-native service discovery.

**Basenames Contract Addresses (Base Sepolia):**

- Registrar Controller: `0x49ae3cc2e3aa768b1e5654f5d3c6002144a59581`
- L2 Resolver: `0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA`

---

## x402 Agent-to-Agent Payment Flow

```
ExecAgent  ->  POST http://localhost:3001/v1/price
           ←  HTTP 402 Payment Required
                { token: "USDC", amount: "0.001", payTo: "0x28be..." }

ExecAgent pays 0.001 USDC on-chain (Base Sepolia)
           ->  POST http://localhost:3001/v1/price
                X-PAYMENT: <txHash:paymentId>
           ←  HTTP 200
                { action: "BUY", confidence: 0.87, price: 3845.13 }

ExecAgent builds ERC-4337 UserOperation -> SwapExecutor.executeSwap()
Uniswap V3 swap executes on-chain
Both agents ERC-8004 reputation scores update
```

---

## Two Agent Types

### Signal Agent (`dolox-signal.base.eth`)

- Exposes an x402-gated HTTP endpoint serving ETH price signals derived from Uniswap V3 TWAP
- Charges 0.001 USDC per request - fees accumulate in its ERC-4337 smart account
- ERC-8004 reputation score increases with every fulfilled request (+5 per signal)

### Execution Agent (`dolox-exec.base.eth`)

- Discovers Signal Agent by resolving `dolox-signal.base.eth` -> reads `endpoint` text record
- Pays for price signal via x402 autonomously
- Submits ERC-4337 UserOperation to call `SwapExecutor.executeSwap()` when signal says BUY
- ERC-8004 reputation score increases with every successful swap (+10 per swap)

---

## Deployed Contracts (Base Sepolia)

### DoloX Protocol Contracts

| Contract                    | Address                                      |
| --------------------------- | -------------------------------------------- |
| AgentRegistry               | `0x71C2CfE30993571D21081Ec78d2F1606f3A28b29` |
| ReputationManager           | `0x2F41d88246899eD9897f61f2317C6397db3849f5` |
| SubnameIssuer               | `0xf6a4f52aED7E8DAf39e6F2F065d925b67CB29AEb` |
| SwapExecutor                | `0xC11499825eD583101708786825cBa8c390D4E347` |
| PaymentVerifier             | `0xF2e0B194805678E6be582ca66AD296234d011ed8` |
| Mock USDC                   | `0x520E3E1ffF40D130377CA18eEda84ccf8E30Ca55` |
| DoloX Pool (WETH/USDC 0.3%) | `0xdcD3c1239bc4F523eC2d20C22E7564477Cf5D1fA` |

### External Protocol Contracts (pre-deployed)

| Contract                   | Address                                      |
| -------------------------- | -------------------------------------------- |
| ERC-4337 EntryPoint v0.7   | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |
| ERC-8004 Identity Registry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| Uniswap V3 Factory         | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` |
| Uniswap SwapRouter02       | `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4` |

---

## Tech Stack

**Smart Contracts**

- Solidity `^0.8.24`
- Foundry (Forge + Cast)
- OpenZeppelin Contracts v5
- ERC-4337 EntryPoint v0.7
- Uniswap V3 SwapRouter02

**Backend / Keeper**

- TypeScript + Node.js
- viem - on-chain reads, Basenames resolution, tx submission
- permissionless.js - ERC-4337 UserOperation builder + Pimlico bundler
- x402 TypeScript SDK - payment server middleware + client
- Express + cors - signal agent HTTP server

**Frontend**

- React + Vite + TypeScript
- viem (pure public client, no wallet required)
- TailwindCSS + shadcn/ui
- Public Base Sepolia RPC

---

## Setup

### Prerequisites

- Node.js >= 20
- Foundry (`curl -L https://foundry.paradigm.xyz | bash`)
- Base Sepolia ETH from [coinbase.com/faucets/base-sepolia-faucet](https://coinbase.com/faucets/base-sepolia-faucet)
- Alchemy API key for Base Sepolia RPC

### Install

```bash
git clone https://github.com/0xEunum/dolox
cd dolox

cd keeper && npm install
cd ../frontend && npm install
cd ../contracts && forge install
forge build
```

### Configure

```bash
cp keeper/.env.example keeper/.env
cp contracts/.env.example contracts/.env
# Fill in all env vars - see keeper/README.md & contracts/README.md
```

### Deploy

```bash
#(Optional)
cd contracts
forge script script/Deploy.s.sol --rpc-url base_sepolia --account <keystore> --broadcast --verify
```

### Register Agents

```bash
forge script script/RegisterAgent.s.sol:RegisterSignalAgent --rpc-url base_sepolia --account <keystore> --broadcast
```

```bash
forge script script/RegisterAgent.s.sol:RegisterExecAgent --rpc-url base_sepolia --account <keystore> --broadcast
```

### Run

```bash
npm run keeper:dev      # starts signalAgent + execAgent
npm run frontend:dev    # starts React dashboard at localhost:8000
```

---

## Demo Walkthrough

1. Two agents live on Base Sepolia with Basenames - `dolox-signal.base.eth` and `dolox-exec.base.eth`
2. Dashboard shows both agents, their Basenames, ERC-8004 IDs, and current reputation scores
3. ExecAgent keeper starts polls SignalAgent endpoint every 30 seconds
4. ExecAgent hits SignalAgent -> receives HTTP 402 -> pays 0.001 USDC via x402
5. SignalAgent verifies payment -> returns `{ action: "BUY", price: 1987.43 }`
6. ExecAgent submits ERC-4337 UserOperation -> `SwapExecutor.executeSwap()` called
7. Uniswap V3 swap transaction confirmed on Base Sepolia - visible on Basescan
8. Both agents' ERC-8004 reputation scores update on-chain
9. Frontend reflects new swap in history and updated scores
10. Zero human clicks throughout the entire flow

---

## Hackathon Tracks

- **Uniswap Foundation** - Agents that trade autonomously and coordinate using Uniswap V3 as the execution and settlement layer
- **ENS** - Basenames text records as machine-readable capability certificates enabling autonomous A2A endpoint discovery - beyond basic name resolution
- **0G Autonomous Agents** - Two autonomous agents collaborating, paying each other, and building verifiable on-chain reputation without human intervention

---

## AI Attribution

See [ATTRIBUTION.md](./ATTRIBUTION.md)

---

## License

MIT [LICENSE.md](./LICENSE)
