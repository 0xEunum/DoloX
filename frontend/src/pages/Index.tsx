import { Header } from "@/components/dolox/Header";
import { AgentCard } from "@/components/dolox/AgentCard";
import { PaymentFeed } from "@/components/dolox/PaymentFeed";
import { SwapHistory } from "@/components/dolox/SwapHistory";
import { PoolStatus } from "@/components/dolox/PoolStatus";
import { CurrentSignal } from "@/components/dolox/CurrentSignal";
import { Architecture } from "@/components/dolox/Architecture";
import { Footer } from "@/components/dolox/Footer";
import { ADDRESSES } from "@/lib/dolox/contracts";

const SIGNAL_CAPS = [
  { label: "agentType", value: "SIGNAL" },
  { label: "pricePerCall", value: "0.001 USDC" },
  { label: "paymentToken", value: "USDC" },
  { label: "canSwap", value: "false" },
  { label: "version", value: "1.0.0" },
  { label: "protocol", value: "dolox" },
];

const EXEC_CAPS = [
  { label: "agentType", value: "EXECUTION" },
  { label: "swapAmountIn", value: "0.001 WETH/tick" },
  { label: "poolFee", value: "3000 (0.3%)" },
  { label: "canSwap", value: "true" },
  { label: "entryPoint", value: "ERC-4337 v0.7" },
  { label: "protocol", value: "dolox" },
];

const Index = () => {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <Header />
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Agent Cards */}
        <section className="grid lg:grid-cols-2 gap-6">
          <AgentCard
            variant="signal"
            basename="dolox-signal.base.eth"
            account={ADDRESSES.SIGNAL_AGENT_ACCOUNT}
            capabilities={SIGNAL_CAPS}
          />
          <AgentCard
            variant="exec"
            basename="dolox-exec.base.eth"
            account={ADDRESSES.EXEC_AGENT_ACCOUNT}
            capabilities={EXEC_CAPS}
          />
        </section>

        {/* Activity Feed */}
        <section className="space-y-6">
          <CurrentSignal />
          <PaymentFeed />
          <SwapHistory />
          <PoolStatus />
        </section>

        {/* Architecture */}
        <Architecture />
      </main>
      <Footer />
    </div>
  );
};

export default Index;
