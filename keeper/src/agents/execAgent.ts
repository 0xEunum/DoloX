import { parseUnits, type Address } from "viem";
import { BasenamesResolver } from "../core/basenamesResolver.js";
import { X402Client } from "../core/x402Client.js";
import { ERC4337Client } from "../core/erc4337.js";

export interface ExecAgentConfig {
  rpcUrl: string;
  bundlerUrl: string;
  privateKey: string;
  agentAccount: string; // exec agent's ERC-4337 smart account
  swapExecutorAddress: string;
  tokenIn: string; // WETH
  tokenOut: string; // USDC
  poolFee: number; // 3000
  swapAmountIn: string; // "0.001" ETH per swap
  signalAgentName: string; // "dolox-signal.base.eth"
  usdcAddress: string;
  pollIntervalMs: number; // 30000 (30 seconds)
}

export class ExecAgent {
  private resolver: BasenamesResolver;
  private x402Client: X402Client;
  private erc4337: ERC4337Client;
  private running: boolean = false;
  private swapCount: number = 0;

  constructor(private config: ExecAgentConfig) {
    this.resolver = new BasenamesResolver(config.rpcUrl);
    this.x402Client = new X402Client(config.rpcUrl, config.privateKey);
    this.erc4337 = new ERC4337Client(
      config.rpcUrl,
      config.bundlerUrl,
      config.privateKey,
      config.agentAccount,
      config.swapExecutorAddress,
    );
  }

  async start() {
    await this.erc4337.init();
    this.running = true;

    console.log(`[ExecAgent] Live — account: ${this.config.agentAccount}`);
    console.log(`[ExecAgent] Basename: dolox-exec.base.eth`);
    console.log(
      `[ExecAgent] Polling every ${this.config.pollIntervalMs / 1000}s`,
    );

    // Start A2A loop
    this._loop();
  }

  stop() {
    this.running = false;
    console.log("[ExecAgent] Stopped");
  }

  private async _loop() {
    while (this.running) {
      try {
        await this._tick();
      } catch (err) {
        console.error("[ExecAgent] Tick error:", err);
      }

      await this._sleep(this.config.pollIntervalMs);
    }
  }

  private async _tick() {
    console.log(`\n[ExecAgent] ── Tick #${++this.swapCount} ──`);

    // ── Step 1: Discover signal endpoint via Basenames ────────────
    let endpoint = await this.resolver.discoverSignalEndpoint(
      this.config.signalAgentName,
    );

    if (!endpoint) {
      endpoint = `http://localhost:${process.env.SIGNAL_PORT ?? "3001"}/v1`;
      console.log(`[ExecAgent] Basenames not resolved — fallback: ${endpoint}`);
    }

    console.log(`[ExecAgent] Resolved endpoint: ${endpoint}`);

    // ── Step 2: Call signal endpoint (x402 auto-handled) ──────────
    const signalUrl = endpoint;
    let signal: any;

    try {
      signal = await this.x402Client.callWithPayment(signalUrl);
    } catch (err) {
      console.error("[ExecAgent] Signal fetch failed:", err);
      return;
    }

    console.log(
      `[ExecAgent] Signal received — action: ${signal.action}, ` +
        `price: ${signal.price}, confidence: ${signal.confidence}`,
    );

    // ── Step 3: Act on signal ─────────────────────────────────────
    if (signal.action !== "BUY") {
      console.log(`[ExecAgent] Signal is ${signal.action} — no swap this tick`);
      return;
    }

    if (signal.confidence < 0.5) {
      console.log(
        `[ExecAgent] Confidence too low (${signal.confidence}) — skipping swap`,
      );
      return;
    }

    // ── Step 4: Submit ERC-4337 UserOp → SwapExecutor ─────────────
    const amountIn = parseUnits(this.config.swapAmountIn, 18); // WETH
    const slippage = 0.005; // 0.5%
    const expectedOut = BigInt(
      Math.floor((signal.price * Number(amountIn)) / 1e18),
    );
    const amountOutMinimum = BigInt(
      Math.floor(Number(expectedOut) * (1 - slippage)),
    );

    console.log(
      `[ExecAgent] Executing swap — ${this.config.swapAmountIn} WETH → USDC`,
    );

    try {
      const txHash = await this.erc4337.executeSwap({
        tokenIn: this.config.tokenIn as Address,
        tokenOut: this.config.tokenOut as Address,
        fee: this.config.poolFee,
        amountIn,
        amountOutMinimum,
      });

      console.log(`[ExecAgent] Swap confirmed: ${txHash}`);
      console.log(
        `[ExecAgent] Basescan: https://sepolia.basescan.org/tx/${txHash}`,
      );
    } catch (err) {
      console.error("[ExecAgent] Swap failed:", err);
    }
  }

  private _sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
