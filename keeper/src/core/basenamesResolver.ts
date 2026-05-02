import {
  createPublicClient,
  http,
  keccak256,
  encodePacked,
  type Address,
} from "viem";
import { baseSepolia } from "viem/chains";

const L2_RESOLVER_ABI = [
  {
    name: "addr",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "node", type: "bytes32" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "text",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "node", type: "bytes32" },
      { name: "key", type: "string" },
    ],
    outputs: [{ name: "", type: "string" }],
  },
] as const;

const L2_RESOLVER = "0x6533C94869D28fAA8dF77cc63f9e2b2D6Cf77eBA" as Address;

// SubnameIssuer ABI — to read the correct node for an agent
const SUBNAME_ISSUER_ABI = [
  {
    name: "getAgentNode",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "bytes32" }],
  },
  {
    name: "accountToName",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "string" }],
  },
] as const;

const SUBNAME_ISSUER = process.env.SUBNAME_ISSUER as Address;

export class BasenamesResolver {
  private client;

  constructor(rpcUrl: string) {
    this.client = createPublicClient({
      chain: baseSepolia,
      transport: http(rpcUrl),
    });
  }

  private namehash(name: string): `0x${string}` {
    let node = ("0x" + "00".repeat(32)) as `0x${string}`;
    if (name === "") return node;
    const labels = name.split(".").reverse();
    for (const label of labels) {
      const labelHash = keccak256(encodePacked(["string"], [label]));
      node = keccak256(encodePacked(["bytes32", "bytes32"], [node, labelHash]));
    }
    return node;
  }

  async readTextRecord(name: string, key: string): Promise<string | null> {
    try {
      const node = this.namehash(name);
      const value = await this.client.readContract({
        address: L2_RESOLVER,
        abi: L2_RESOLVER_ABI,
        functionName: "text",
        args: [node, key],
      });
      return value || null;
    } catch {
      return null;
    }
  }

  async discoverSignalEndpoint(agentName: string): Promise<string | null> {
    // Step 1: try standard namehash resolution
    const endpoint = await this.readTextRecord(agentName, "endpoint");
    if (endpoint) {
      console.log(`[BasenamesResolver] Resolved via namehash: ${endpoint}`);
      return endpoint;
    }

    // Step 2: fallback — read node directly from SubnameIssuer using agent account
    // Agent account is derived from agentName prefix
    try {
      if (!SUBNAME_ISSUER) return null;

      const SIGNAL_ACCOUNT = process.env.SIGNAL_AGENT_ACCOUNT as Address;
      if (!SIGNAL_ACCOUNT) return null;

      const node = await this.client.readContract({
        address: SUBNAME_ISSUER,
        abi: SUBNAME_ISSUER_ABI,
        functionName: "getAgentNode",
        args: [SIGNAL_ACCOUNT],
      });

      const ep = await this.client.readContract({
        address: L2_RESOLVER,
        abi: L2_RESOLVER_ABI,
        functionName: "text",
        args: [node, "endpoint"],
      });

      if (ep) {
        console.log(
          `[BasenamesResolver] Resolved via SubnameIssuer node: ${ep}`,
        );
        return ep;
      }
    } catch {
      // fall through
    }

    return null;
  }
}
