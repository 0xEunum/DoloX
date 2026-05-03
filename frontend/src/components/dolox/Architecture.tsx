import { ArrowRight, ArrowDown } from "lucide-react";

export function Architecture() {
  return (
    <section className="rounded-xl border border-border bg-card p-5 sm:p-8">
      <div className="mb-6">
        <h3 className="text-sm font-semibold">Protocol Architecture</h3>
        <p className="text-xs text-muted-foreground mt-1">
          A2A runtime loop · x402 payments · Uniswap V3 · ERC-8004 reputation
        </p>
      </div>

      <div className="flex flex-col gap-6">
        {/* Top row: Signal -> Exec */}
        <div className="flex flex-col md:flex-row items-stretch md:items-center justify-center gap-4 md:gap-2">
          <ArchBox accent="primary" title="Signal Agent">
            <p className="text-[11px] text-muted-foreground">Basenames</p>
            <p className="font-mono text-xs text-foreground/90">
              dolox-signal.base.eth
            </p>
            <p className="text-[11px] text-muted-foreground mt-1">
              Price Signal · TWAP + Uniswap API
            </p>
          </ArchBox>

          <Connector label="x402 USDC" />

          <ArchBox accent="warning" title="Exec Agent">
            <p className="text-[11px] text-muted-foreground">
              ERC-4337 UserOp
            </p>
            <p className="font-mono text-xs text-foreground/90">
              Pimlico Bundler
            </p>
          </ArchBox>
        </div>

        <div className="flex justify-center md:justify-end md:pr-[12%]">
          <ArrowDown className="w-5 h-5 text-primary" />
        </div>

        {/* Second row: SwapExecutor -> Uniswap -> Reputation */}
        <div className="flex flex-col md:flex-row items-stretch md:items-center justify-center gap-4 md:gap-2">
          <ArchBox accent="primary" title="SwapExecutor">
            <p className="text-[11px] text-muted-foreground">
              Validates + relays user op
            </p>
          </ArchBox>
          <Connector label="swap" />
          <ArchBox accent="success" title="Uniswap V3">
            <p className="font-mono text-xs">WETH → USDC</p>
            <p className="text-[11px] text-muted-foreground mt-1">
              0.3% fee tier
            </p>
          </ArchBox>
          <Connector label="record" />
          <ArchBox accent="warning" title="ReputationManager">
            <p className="text-[11px] text-muted-foreground">
              ERC-8004 · Score++
            </p>
          </ArchBox>
        </div>
      </div>
    </section>
  );
}

function ArchBox({
  title,
  children,
  accent,
}: {
  title: string;
  children: React.ReactNode;
  accent: "primary" | "success" | "warning";
}) {
  const map = {
    primary: "border-primary/40",
    success: "border-success/40",
    warning: "border-warning/40",
  };
  const titleColor = {
    primary: "text-primary",
    success: "text-success",
    warning: "text-warning",
  };
  return (
    <div
      className={`flex-1 min-w-[160px] rounded-lg border-2 border-dashed ${map[accent]} bg-background/40 p-3`}
    >
      <div
        className={`text-[10px] uppercase tracking-widest font-semibold ${titleColor[accent]}`}
      >
        {title}
      </div>
      <div className="mt-1 space-y-0.5">{children}</div>
    </div>
  );
}

function Connector({ label }: { label: string }) {
  return (
    <div className="flex md:flex-col items-center justify-center gap-1 md:gap-0.5 md:px-1">
      <span className="font-mono text-[10px] uppercase tracking-widest text-primary md:order-1">
        {label}
      </span>
      <ArrowRight className="hidden md:block w-5 h-5 text-primary md:order-2" />
      <ArrowDown className="md:hidden w-4 h-4 text-primary" />
    </div>
  );
}