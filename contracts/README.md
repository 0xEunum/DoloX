# DoloX Contracts

Solidity smart contracts for the DoloX protocol. Built with Foundry, OpenZeppelin, and deployed on Base Sepolia.

## Contracts

### `AgentRegistry.sol`

Protocol-level agent identity registry. Tracks all Signal / Execution / Hybrid agents. Source of truth for the DoloX A2A runtime loop. Each agent is registered with a Basename, agent type, and owner EOA.

### `ReputationManager.sol`

On-chain reputation scoring for agents. Score starts at 100, max 1000.

- `+10` per successful Uniswap swap (`SWAP_SUCCESS`)
- `+5` per fulfilled x402 signal request (`SIGNAL_FULFILLED`)
- `-5` per failed swap attempt (`SWAP_FAILED`)
- `-3` per invalid signal (`SIGNAL_INVALID`)

Only authorized callers (`SwapExecutor`, `PaymentVerifier`, agent owner EOA) can update scores.

### `SubnameIssuer.sol`

Registers agent Basenames (`dolox-signal.base.eth`) and writes machine-readable ENS text records — endpoint URL, capabilities, payment token, price per call, agent type.

### `SwapExecutor.sol`

Called by the exec agent's ERC-4337 smart account via UserOp. Executes `exactInputSingle` swaps on Uniswap V3. Validates agent registration before executing. Updates reputation on success and failure.

### `PaymentVerifier.sol`

On-chain x402 payment proof verifier. Signal agent submits payment proof to earn reputation. Validates ECDSA signature from payer's EOA.

## Deployed Addresses (Base Sepolia)

| Contract          | Address                                      |
| ----------------- | -------------------------------------------- |
| AgentRegistry     | `0x71C2CfE30993571D21081Ec78d2F1606f3A28b29` |
| ReputationManager | `0x2F41d88246899eD9897f61f2317C6397db3849f5` |
| SubnameIssuer     | `0xf6a4f52aED7E8DAf39e6F2F065d925b67CB29AEb` |
| SwapExecutor      | `0xC11499825eD583101708786825cBa8c390D4E347` |
| PaymentVerifier   | `0xF2e0B194805678E6be582ca66AD296234d011ed8` |
| Mock USDC         | `0x520E3E1ffF40D130377CA18eEda84ccf8E30Ca55` |
| DoloX Pool        | `0xdcD3c1239bc4F523eC2d20C22E7564477Cf5D1fA` |

## Setup

```bash
cd contracts
```

## Configure

```bash
cp .env.example .env
# Fill in all env vars
BASE_SEPOLIA_RPC_URL=
ETHERSCAN_API_KEY=
```

```bash
forge install
forge build
forge test
```

## Deploy

```bash
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --account <keystore> \
  --broadcast \
  --verify
```

## Test

```bash
forge test -vv
forge coverage
```

## Stack

- Solidity `^0.8.24`
- Foundry (Forge + Cast)
- OpenZeppelin Contracts v5
- ERC-4337 EntryPoint v0.7
- Uniswap V3 SwapRouter02
