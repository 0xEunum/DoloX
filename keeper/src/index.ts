import "dotenv/config";
import { SignalAgent } from "./agents/signalAgent.js";
import { ExecAgent } from "./agents/execAgent.js";

function requireEnv(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing env var: ${key}`);
  return val;
}

async function main() {
  console.log("╔══════════════════════════════╗");
  console.log("║   DoloX Keeper Starting...   ║");
  console.log("╚══════════════════════════════╝\n");

  const rpcUrl = requireEnv("BASE_SEPOLIA_RPC_URL");
  const bundlerUrl = requireEnv("BUNDLER_URL");
  const usdcAddress = requireEnv("MOCK_USDC");
  const poolAddress = requireEnv("DOLOX_POOL");

  // ── Start Signal Agent ─────────────────────────────────────────
  const signalAgent = new SignalAgent(
    rpcUrl,
    requireEnv("SIGNAL_AGENT_ACCOUNT"),
    usdcAddress,
    poolAddress,
    requireEnv("REPUTATION_MANAGER"),
    requireEnv("SIGNAL_AGENT_OWNER_PRIVATE_KEY"),
    parseInt(process.env.SIGNAL_PORT ?? "3001"),
  );

  signalAgent.start();

  // Small delay so signal agent is up before exec agent polls it
  await new Promise((r) => setTimeout(r, 2000));

  // ── Start Execution Agent ──────────────────────────────────────
  const execAgent = new ExecAgent({
    rpcUrl,
    bundlerUrl,
    privateKey: requireEnv("EXEC_AGENT_OWNER_PRIVATE_KEY"),
    agentAccount: requireEnv("EXEC_AGENT_ACCOUNT"),
    swapExecutorAddress: requireEnv("SWAP_EXECUTOR"),
    tokenIn: requireEnv("WETH"),
    tokenOut: usdcAddress,
    poolFee: parseInt(process.env.POOL_FEE ?? "3000"),
    swapAmountIn: "0.001",
    signalAgentName: "dolox-signal.base.eth",
    usdcAddress,
    pollIntervalMs: 30_000,
  });

  await execAgent.start();

  // ── Graceful shutdown ──────────────────────────────────────────
  process.on("SIGINT", () => {
    console.log("\n[Keeper] Shutting down...");
    execAgent.stop();
    process.exit(0);
  });
}

main().catch((err) => {
  console.error("[Keeper] Fatal error:", err);
  process.exit(1);
});
