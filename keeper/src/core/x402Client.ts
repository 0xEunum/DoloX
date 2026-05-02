import {
  createWalletClient,
  createPublicClient,
  http,
  parseUnits,
  type Address,
  type WalletClient,
  type Hash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { BasenamesResolver } from "./basenamesResolver.js";

// ERC20 ABI — transfer only
const ERC20_ABI = [
  {
    name: "transfer",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

export interface PaymentRequirement {
  token: Address;
  amount: string;
  payTo: Address;
  chainId: number;
}

export interface X402PaymentResult {
  txHash: Hash;
  paymentId: string;
  paymentHeader: string; // "txHash:paymentId" — sent as X-PAYMENT header
}

export class X402Client {
  private walletClient: WalletClient;
  private publicClient;
  private resolver: BasenamesResolver;
  private account;

  constructor(rpcUrl: string, privateKey: string) {
    this.account = privateKeyToAccount(privateKey as `0x${string}`);

    this.walletClient = createWalletClient({
      account: this.account,
      chain: baseSepolia,
      transport: http(rpcUrl),
    });

    this.publicClient = createPublicClient({
      chain: baseSepolia,
      transport: http(rpcUrl),
    });

    this.resolver = new BasenamesResolver(rpcUrl);
  }

  /// @notice Discover signal agent endpoint from Basenames text record
  async discoverEndpoint(agentName: string): Promise<string | null> {
    return this.resolver.discoverSignalEndpoint(agentName);
  }

  /// @notice Pay for a service via x402 — transfers USDC + returns payment header
  async pay(requirement: PaymentRequirement): Promise<X402PaymentResult> {
    const amount = parseUnits(requirement.amount, 6);

    const txHash = await this.walletClient.writeContract({
      address: requirement.token,
      abi: ERC20_ABI,
      functionName: "transfer",
      args: [requirement.payTo, amount],
    });

    await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    await new Promise((r) => setTimeout(r, 3000)); // let RPC index the logs

    // Use :: so split never collides with 0x hex chars
    const paymentId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const paymentHeader = `${txHash}::${paymentId}`;

    return { txHash, paymentId, paymentHeader };
  }

  /// @notice Full x402 flow: call endpoint → if 402 → pay → retry with proof
  async callWithPayment(url: string, body?: object): Promise<any> {
    // First attempt — no payment header
    const firstRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });

    // Got signal directly (shouldn't happen in production but good for testing)
    if (firstRes.ok) return firstRes.json();

    // HTTP 402 → parse payment requirement
    if (firstRes.status !== 402) {
      throw new Error(`Unexpected status: ${firstRes.status}`);
    }

    const paymentData = await firstRes.json();
    const requirement: PaymentRequirement = paymentData.x402;

    console.log(
      `[x402Client] 402 received — paying ${requirement.amount} USDC to ${requirement.payTo}`,
    );

    // Pay
    const payment = await this.pay(requirement);

    console.log(`[x402Client] Payment sent: ${payment.txHash}`);

    // Retry with payment proof in header
    const secondRes = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-PAYMENT": payment.paymentHeader,
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!secondRes.ok) {
      throw new Error(`Request failed after payment: ${secondRes.status}`);
    }

    return secondRes.json();
  }
}
