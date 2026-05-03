# AI Attribution

This project was built at ETHGlobal OpenAgents 2026 with significant AI assistance throughout.

## AI Tools Used

### Perplexity AI (Primary — Architecture + Development)

Used throughout the entire project for:

- Protocol architecture design — ERC-4337 + Basenames + x402 + Uniswap V3 integration pattern
- Smart contract logic — `SwapExecutor`, `ReputationManager`, `AgentRegistry`, `SubnameIssuer` implementation guidance and review
- Keeper TypeScript — full `erc4337.ts` (UserOp builder, Pimlico v0.7 JSON-RPC format), `x402Server.ts`, `x402Client.ts`, `basenamesResolver.ts`, `priceOracle.ts` debug and iteration
- Debugging — ERC-4337 v0.7 packed struct vs flat JSON-RPC field format, x402 payment separator fix, Uniswap API response field discovery
- All README files and documentation

### Lovable (Frontend Scaffolding)

Used to generate the initial React frontend dashboard based on a detailed prompt describing the DoloX protocol, contract ABIs, and component requirements. Minor manual fixes applied post-generation (CORS, RPC URL, block range for getLogs, parseAbiItem for event filters).

### Claude / Cursor (Code Completion)

Used for inline code completion and Solidity contract comments throughout development.

## Human Contributions

- Protocol concept and design decisions
- Contract architecture and security review
- Keeper agent logic and flow design
- Integration debugging and testing
- Deployment and configuration
- Demo video recording and editing
- All final decisions on implementation approach

## Summary

AI was used as a development accelerator — every line of code was reviewed, understood, and intentionally chosen by the developer. The core protocol ideas, architecture decisions, and integration strategy are original work.
