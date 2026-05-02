import type { Request, Response, NextFunction } from "express";
import { type Address, createPublicClient, http, parseUnits } from "viem";
import { baseSepolia } from "viem/chains";

export interface PaymentRequirement {
  token: Address;
  amount: string;
  payTo: Address;
  network: string;
  chainId: number;
  description: string;
}

export interface VerifiedPayment {
  paymentId: string;
  payer: Address;
  amount: bigint;
  verified: boolean;
}

const USDC_ABI = [
  {
    name: "Transfer",
    type: "event",
    inputs: [
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
  },
] as const;

export class X402Server {
  private client;
  private paymentAddress: Address;
  private usdcAddress: Address;
  private pricePerCall: bigint;
  private verifiedPayments = new Set<string>();

  constructor(
    rpcUrl: string,
    paymentAddress: string,
    usdcAddress: string,
    pricePerCall: string = "0.001",
  ) {
    this.client = createPublicClient({
      chain: baseSepolia,
      transport: http(rpcUrl),
    });
    this.paymentAddress = paymentAddress as Address;
    this.usdcAddress = usdcAddress as Address;
    this.pricePerCall = parseUnits(pricePerCall, 6);
  }

  buildPaymentRequirement(): PaymentRequirement {
    return {
      token: this.usdcAddress,
      amount: "0.001",
      payTo: this.paymentAddress,
      network: "base-sepolia",
      chainId: 84532,
      description: "DoloX Signal — 0.001 USDC per price signal",
    };
  }

  middleware() {
    return async (req: Request, res: Response, next: NextFunction) => {
      const paymentHeader = req.headers["x-payment"] as string | undefined;

      if (!paymentHeader) {
        res.status(402).json({
          error: "Payment Required",
          x402: this.buildPaymentRequirement(),
          message: "Include X-PAYMENT header with payment proof",
        });
        return;
      }

      const verified = await this.verifyPaymentHeader(paymentHeader);
      if (!verified) {
        res.status(402).json({
          error: "Invalid Payment",
          message: "Payment proof invalid, expired, or already used",
        });
        return;
      }

      (req as any).paymentVerified = true;
      (req as any).paymentId = paymentHeader;
      next();
    };
  }

  private async verifyPaymentHeader(paymentHeader: string): Promise<boolean> {
    try {
      // Format: "txHash::paymentId" — double colon avoids collision with 0x hex
      const separatorIdx = paymentHeader.indexOf("::");
      if (separatorIdx === -1) return false;

      const txHash = paymentHeader.slice(0, separatorIdx);
      const paymentId = paymentHeader.slice(separatorIdx + 2);

      if (!txHash || !paymentId) return false;

      // Replay protection
      if (this.verifiedPayments.has(paymentId)) return false;

      // Verify on-chain receipt
      const receipt = await this.client.getTransactionReceipt({
        hash: txHash as `0x${string}`,
      });

      if (!receipt || receipt.status !== "success") return false;

      // Retry getLogs up to 5x — guards against RPC indexing lag
      let transferLogs: any[] = [];
      for (let attempt = 0; attempt < 5; attempt++) {
        transferLogs = await this.client.getLogs({
          address: this.usdcAddress,
          event: USDC_ABI[0],
          args: { to: this.paymentAddress },
          fromBlock: receipt.blockNumber,
          toBlock: receipt.blockNumber,
        });
        if (transferLogs.length > 0) break;
        await new Promise((r) => setTimeout(r, 1000));
      }

      const validTransfer = transferLogs.some(
        (log: any) => BigInt(log.args.value) >= this.pricePerCall,
      );

      if (!validTransfer) return false;

      this.verifiedPayments.add(paymentId);
      return true;
    } catch {
      return false;
    }
  }
}
