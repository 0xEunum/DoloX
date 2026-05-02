import express from "express";
import cors from "cors";
import {
  createWalletClient,
  createPublicClient,
  http,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { X402Server } from "../core/x402Server.js";
import { PriceOracle } from "../core/priceOracle.js";

const REPUTATION_ABI = [
  {
    name: "recordEvent",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "account", type: "address" },
      { name: "eventType", type: "uint8" },
    ],
    outputs: [],
  },
] as const;

export class SignalAgent {
  private app = express();
  private x402: X402Server;
  private oracle: PriceOracle;
  private walletClient: any;

  constructor(
    private rpcUrl: string,
    private agentAccount: string,
    private usdcAddress: string,
    private poolAddress: string,
    private reputationAddress: string,
    private ownerPrivateKey: string,
    private port: number = 3001,
  ) {
    this.x402 = new X402Server(rpcUrl, agentAccount, usdcAddress);
    this.oracle = new PriceOracle(rpcUrl, poolAddress, true);

    // ← add wallet client for on-chain reputation updates
    this.walletClient = createWalletClient({
      chain: baseSepolia,
      transport: http(rpcUrl),
      account: privateKeyToAccount(ownerPrivateKey as `0x${string}`),
    });

    this.app.use(cors());
    this.app.use(express.json());
    this._setupRoutes();
  }

  private _setupRoutes() {
    this.app.get("/health", (_, res) => {
      res.json({
        status: "live",
        agent: "dolox-signal",
        account: this.agentAccount,
        basename: "dolox-signal.base.eth",
      });
    });

    this.app.post("/v1/price", this.x402.middleware(), async (_, res) => {
      try {
        const signal = await this.oracle.getPriceSignal();

        console.log(
          `[SignalAgent] Fulfilled request — action: ${signal.action}, price: ${signal.price}`,
        );

        res.json({
          action: signal.action,
          price: signal.price,
          twapPrice: signal.twapPrice,
          confidence: signal.confidence,
          timestamp: signal.timestamp,
          agent: "dolox-signal.base.eth",
        });
        this.walletClient
          .writeContract({
            address: this.reputationAddress as Address,
            abi: REPUTATION_ABI,
            functionName: "recordEvent",
            args: [this.agentAccount as Address, 1], // 1 = SIGNAL_FULFILLED
          })
          .then((hash: string) => {
            console.log(`[SignalAgent] Reputation updated: ${hash}`);
          })
          .catch((e: any) => {
            console.warn(
              `[SignalAgent] Reputation update skipped:`,
              e.shortMessage ?? e.message,
            );
          });
      } catch (err) {
        console.error("[SignalAgent] Price fetch failed:", err);
        res.status(500).json({ error: "Price fetch failed" });
      }
    });

    this.app.get("/v1/capabilities", (_, res) => {
      res.json(this.x402.buildPaymentRequirement());
    });

    this.app.get("/v1/signal", async (_, res) => {
      try {
        const signal = await this.oracle.getPriceSignal();
        res.json({
          action: signal.action,
          price: signal.price,
          confidence: signal.confidence,
          source: signal.source,
          timestamp: signal.timestamp,
        });
      } catch {
        res.status(500).json({ error: "failed" });
      }
    });
  }

  start() {
    this.app.listen(this.port, () => {
      console.log(`[SignalAgent] Live at http://localhost:${this.port}`);
      console.log(`[SignalAgent] Basename: dolox-signal.base.eth`);
      console.log(`[SignalAgent] Account: ${this.agentAccount}`);
      console.log(`[SignalAgent] Price endpoint: POST /v1/price (x402 gated)`);
    });
  }
}
