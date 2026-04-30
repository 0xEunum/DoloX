import express from "express";
import { X402Server } from "../core/x402Server.js";
import { PriceOracle } from "../core/priceOracle.js";

export class SignalAgent {
  private app = express();
  private x402: X402Server;
  private oracle: PriceOracle;

  constructor(
    private rpcUrl: string,
    private agentAccount: string, // signal agent's smart account
    private usdcAddress: string,
    private poolAddress: string,
    private port: number = 3001,
  ) {
    this.x402 = new X402Server(rpcUrl, agentAccount, usdcAddress);
    this.oracle = new PriceOracle(rpcUrl, poolAddress);

    this.app.use(express.json());
    this._setupRoutes();
  }

  private _setupRoutes() {
    // ── Health check ─────────────────────────────────────────────
    this.app.get("/health", (_, res) => {
      res.json({
        status: "live",
        agent: "signal-dolox",
        account: this.agentAccount,
        basename: "signal-dolox.base.eth",
      });
    });

    // ── x402-gated price signal endpoint ─────────────────────────
    this.app.post(
      "/v1/price",
      this.x402.middleware(), // ← 402 gate
      async (_, res) => {
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
            agent: "signal-dolox.base.eth",
          });
        } catch (err) {
          console.error("[SignalAgent] Price fetch failed:", err);
          res.status(500).json({ error: "Price fetch failed" });
        }
      },
    );

    // ── Capability manifest (public) ─────────────────────────────
    this.app.get("/v1/capabilities", (_, res) => {
      res.json(this.x402.buildPaymentRequirement());
    });
  }

  start() {
    this.app.listen(this.port, () => {
      console.log(`[SignalAgent] Live at http://localhost:${this.port}`);
      console.log(`[SignalAgent] Basename: signal-dolox.base.eth`);
      console.log(`[SignalAgent] Account:  ${this.agentAccount}`);
      console.log(`[SignalAgent] Price endpoint: POST /v1/price (x402 gated)`);
    });
  }
}
