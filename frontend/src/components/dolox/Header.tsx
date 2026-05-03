import { useEffect, useState } from "react";
import { readClient } from "@/lib/dolox/chain";
import { ADDRESSES, AGENT_REGISTRY_ABI } from "@/lib/dolox/contracts";

export function Header() {
  const [totalAgents, setTotalAgents] = useState<bigint | null>(null);
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    let cancelled = false;
    const fetchTotal = async () => {
      try {
        const total = (await readClient.readContract({
          address: ADDRESSES.AGENT_REGISTRY,
          abi: AGENT_REGISTRY_ABI,
          functionName: "totalAgents",
        })) as bigint;
        if (!cancelled) setTotalAgents(total);
      } catch {
        if (!cancelled) setTotalAgents(null);
      }
    };
    fetchTotal();
    const i = setInterval(fetchTotal, 30_000);
    return () => {
      cancelled = true;
      clearInterval(i);
    };
  }, []);

  useEffect(() => {
    const i = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(i);
  }, []);

  return (
    <header className="relative overflow-hidden border-b border-border">
      <div className="absolute inset-0 grid-bg opacity-40 pointer-events-none" />
      <div className="absolute inset-0 bg-gradient-to-b from-primary/5 to-transparent pointer-events-none" />
      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10 flex flex-col lg:flex-row lg:items-end lg:justify-between gap-6">
        <div>
          <div className="flex items-center gap-3 mb-3">
            <span className="relative flex h-2.5 w-2.5">
              <span className="absolute inline-flex h-full w-full rounded-full bg-success opacity-75 animate-ping" />
              <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-success" />
            </span>
            <span className="font-mono text-xs uppercase tracking-widest text-success">
              LIVE on Base Sepolia
            </span>
          </div>
          <h1 className="text-4xl sm:text-5xl font-bold tracking-tight">
            <span className="bg-gradient-to-r from-foreground to-primary bg-clip-text text-transparent">
              DoloX
            </span>{" "}
            <span className="text-foreground/80">Protocol</span>
          </h1>
          <p className="mt-3 max-w-2xl text-muted-foreground text-sm sm:text-base">
            Autonomous DeFi agents with on-chain identity, x402 payments and
            Uniswap V3 execution.
          </p>
        </div>

        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          <Stat label="Total Agents" value={totalAgents?.toString() ?? "—"} />
          <Stat label="Network" value="Base Sepolia" mono={false} />
          <Stat
            label="Local Time"
            value={now.toLocaleTimeString([], { hour12: false })}
          />
        </div>
      </div>
    </header>
  );
}

function Stat({
  label,
  value,
  mono = true,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div className="rounded-lg border border-border bg-card/60 backdrop-blur px-3 py-2 min-w-[100px]">
      <div className="text-[10px] uppercase tracking-widest text-muted-foreground">
        {label}
      </div>
      <div
        className={`mt-0.5 text-sm sm:text-base font-semibold ${
          mono ? "font-mono" : ""
        }`}
      >
        {value}
      </div>
    </div>
  );
}