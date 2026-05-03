export const ADDRESSES = {
  AGENT_REGISTRY: "0x71C2CfE30993571D21081Ec78d2F1606f3A28b29",
  REPUTATION_MGR: "0x2F41d88246899eD9897f61f2317C6397db3849f5",
  SWAP_EXECUTOR: "0xC11499825eD583101708786825cBa8c390D4E347",
  MOCK_USDC: "0x520E3E1ffF40D130377CA18eEda84ccf8E30Ca55",
  WETH: "0x4200000000000000000000000000000000000006",
  DOLOX_POOL: "0xdcD3c1239bc4F523eC2d20C22E7564477Cf5D1fA",
  SIGNAL_AGENT_ACCOUNT: "0x28be458F90A200D4A62A352B981B1ebc80dcE21D",
  EXEC_AGENT_ACCOUNT: "0x8CF9CbFBaD0140629Afec50ED56955072f2Cea10",
} as const;

export const AGENT_REGISTRY_ABI = [
  {
    type: "function",
    name: "getAgent",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "agentId", type: "uint256" },
          { name: "account", type: "address" },
          { name: "owner", type: "address" },
          { name: "ensName", type: "string" },
          { name: "agentType", type: "uint8" },
          { name: "active", type: "bool" },
          { name: "registeredAt", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isRegistered",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalAgents",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

export const REPUTATION_ABI = [
  {
    type: "function",
    name: "getScore",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getFullScore",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "score", type: "uint256" },
          { name: "totalSwaps", type: "uint256" },
          { name: "successfulSwaps", type: "uint256" },
          { name: "totalSignals", type: "uint256" },
          { name: "fulfilledSignals", type: "uint256" },
          { name: "lastUpdated", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getSuccessRate",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

export const SWAP_EXECUTOR_ABI = [
  {
    type: "event",
    name: "SwapExecuted",
    inputs: [
      { name: "agentAccount", type: "address", indexed: true },
      { name: "tokenIn", type: "address", indexed: true },
      { name: "tokenOut", type: "address", indexed: true },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "fee", type: "uint24", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

export const ERC20_ABI = [
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "Transfer",
    inputs: [
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
  },
] as const;