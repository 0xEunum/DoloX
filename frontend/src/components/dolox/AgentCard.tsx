import { useEffect, useState } from "react";
import { Activity, Cpu, Coins, AlertCircle } from "lucide-react";
import { readClient } from "@/lib/dolox/chain";
import {
  ADDRESSES,
  AGENT_REGISTRY_ABI,
  ERC20_ABI,
  REPUTATION_ABI,
} from "@/lib/dolox/contracts";
import { AddressTag } from "./AddressTag";
import { formatAmount, formatDate } from "@/lib/dolox/utils";

interface AgentInfo {
  agentId: bigint;
  account: string;
  owner: string;
  ensName: string;
  agentType: number;
  active: boolean;
  registeredAt: bigint;
}

interface FullScore {
  score: bigint;
  totalSwaps: bigint;
  successfulSwaps: bigint;
  totalSignals: bigint;
  fulfilledSignals: bigint;
  lastUpdated: bigint;
}

interface Capability {
  label: string;
  value: string;
}

interface AgentCardProps {
  variant: "signal" | "exec";
  basename: string;
  account: string;
  capabilities: Capability[];
}

export function AgentCard({
  variant,
  basename,
  account,
  capabilities,
}: AgentCardProps) {
  const [info, setInfo] = useState<AgentInfo | null>(null);
  const [score, setScore] = useState<FullScore | null>(null);
  const [successRate, setSuccessRate] = useState<bigint | null>(null);
  const [usdc, setUsdc] = useState<bigint | null>(null);
  const [weth, setWeth] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const isSignal = variant === "signal";

  const fetchAll = async () => {
    setError(null);
    try {
      const [agent, full, rate, usdcBal, wethBal] = await Promise.all([
        readClient.readContract({
          address: ADDRESSES.AGENT_REGISTRY,
          abi: AGENT_REGISTRY_ABI,
          functionName: "getAgent",
          args: [account],
        }),
        readClient.readContract({
          address: ADDRESSES.REPUTATION_MGR,
          abi: REPUTATION_ABI,
          functionName: "getFullScore",
          args: [account],
        }),
        readClient.readContract({
          address: ADDRESSES.REPUTATION_MGR,
          abi: REPUTATION_ABI,
          functionName: "getSuccessRate",
          args: [account],
        }),
        readClient.readContract({
          address: ADDRESSES.MOCK_USDC,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: [account],
        }),
        readClient.readContract({
          address: ADDRESSES.WETH,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: [account],
        }),
      ]);
      setInfo(agent as AgentInfo);
      setScore(full as FullScore);
      setSuccessRate(rate as bigint);
      setUsdc(usdcBal as bigint);
      setWeth(wethBal as bigint);
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Failed to fetch agent data");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAll();
    const i = setInterval(fetchAll, 30_000);
    return () => clearInterval(i);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account]);

  const accentClass = isSignal ? "text-primary" : "text-warning";
  const accentBg = isSignal ? "bg-primary/15" : "bg-warning/15";
  const accentBorder = isSignal ? "border-primary/30" : "border-warning/30";
  const badgeLabel = isSignal ? "SIGNAL AGENT" : "EXEC AGENT";

  const scoreNum = Number(score?.score ?? 0n);
  const pct = Math.min(100, (scoreNum / 1000) * 100);

  return (
    <div
      className={`relative rounded-xl border ${accentBorder} bg-card overflow-hidden`}
    >
      <div
        className={`absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-${
          isSignal ? "primary" : "warning"
        } to-transparent`}
      />
      <div className="p-5 sm:p-6 flex flex-col gap-5">
        {/* Header */}
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-3">
            <div
              className={`flex items-center justify-center w-10 h-10 rounded-lg ${accentBg} ${accentClass}`}
            >
              {isSignal ? (
                <Activity className="w-5 h-5" />
              ) : (
                <Cpu className="w-5 h-5" />
              )}
            </div>
            <div>
              <span
                className={`inline-block text-[10px] font-semibold tracking-widest px-2 py-0.5 rounded ${accentBg} ${accentClass}`}
              >
                {badgeLabel}
              </span>
              <div className="mt-1 font-mono text-sm sm:text-base text-foreground/90">
                {basename}
              </div>
            </div>
          </div>
          <StatusPill active={info?.active ?? true} />
        </div>

        {/* Address + IDs */}
        <div className="rounded-lg border border-border bg-background/60 p-3 grid sm:grid-cols-3 gap-3 text-xs">
          <Field label="Smart Account">
            <AddressTag address={account} />
          </Field>
          <Field label="Agent ID">
            <span className="font-mono">
              {loading ? "…" : info?.agentId?.toString() ?? "—"}
            </span>
          </Field>
          <Field label="Registered">
            <span className="font-mono">
              {loading ? "…" : formatDate(info?.registeredAt)}
            </span>
          </Field>
        </div>

        {/* Balances */}
        <div>
          <SectionTitle icon={<Coins className="w-3.5 h-3.5" />}>
            Balances
          </SectionTitle>
          <div className="grid grid-cols-2 gap-3 mt-2">
            <Balance
              symbol="USDC"
              value={usdc}
              decimals={6}
              display={2}
              loading={loading}
            />
            <Balance
              symbol="WETH"
              value={weth}
              decimals={18}
              display={4}
              loading={loading}
            />
          </div>
        </div>

        {/* Reputation */}
        <div>
          <SectionTitle icon={<Activity className="w-3.5 h-3.5" />}>
            Reputation (ERC-8004)
          </SectionTitle>
          <div className="mt-2 rounded-lg border border-border bg-background/60 p-3">
            <div className="flex items-end justify-between mb-2">
              <div className="flex items-baseline gap-1">
                <span className="font-mono text-3xl font-semibold text-foreground">
                  {loading ? "…" : scoreNum}
                </span>
                <span className="font-mono text-xs text-muted-foreground">
                  / 1000
                </span>
              </div>
              <span className="font-mono text-xs text-success">
                {successRate !== null
                  ? `${Number(successRate)}% success`
                  : ""}
              </span>
            </div>
            <div className="h-1.5 w-full rounded-full bg-secondary overflow-hidden">
              <div
                className={`h-full ${
                  isSignal ? "bg-primary" : "bg-warning"
                } transition-all duration-500`}
                style={{ width: `${pct}%` }}
              />
            </div>
            <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
              {isSignal ? (
                <>
                  <Mini
                    label="Fulfilled signals"
                    value={`${score?.fulfilledSignals ?? 0n}`}
                  />
                  <Mini
                    label="Total signals"
                    value={`${score?.totalSignals ?? 0n}`}
                  />
                </>
              ) : (
                <>
                  <Mini
                    label="Successful swaps"
                    value={`${score?.successfulSwaps ?? 0n}`}
                  />
                  <Mini
                    label="Total swaps"
                    value={`${score?.totalSwaps ?? 0n}`}
                  />
                </>
              )}
            </div>
          </div>
        </div>

        {/* Capabilities */}
        <div>
          <SectionTitle icon={<Cpu className="w-3.5 h-3.5" />}>
            Capabilities
          </SectionTitle>
          <div className="mt-2 rounded-lg border border-dashed border-border bg-background/40 p-3 grid grid-cols-2 gap-y-2 gap-x-4 text-xs">
            {capabilities.map((c) => (
              <div key={c.label} className="flex justify-between gap-2">
                <span className="text-muted-foreground">{c.label}</span>
                <span className="font-mono text-foreground/90 truncate">
                  {c.value}
                </span>
              </div>
            ))}
          </div>
        </div>

        {error && (
          <div className="flex items-center gap-2 rounded border border-destructive/30 bg-destructive/10 px-3 py-2 text-xs text-destructive">
            <AlertCircle className="w-3.5 h-3.5" />
            <span className="flex-1 truncate">{error}</span>
            <button
              onClick={fetchAll}
              className="font-semibold underline-offset-2 hover:underline"
            >
              Retry
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-widest text-muted-foreground mb-1">
        {label}
      </div>
      <div>{children}</div>
    </div>
  );
}

function SectionTitle({
  children,
  icon,
}: {
  children: React.ReactNode;
  icon?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-widest text-muted-foreground">
      {icon}
      {children}
    </div>
  );
}

function Balance({
  symbol,
  value,
  decimals,
  display,
  loading,
}: {
  symbol: string;
  value: bigint | null;
  decimals: number;
  display: number;
  loading: boolean;
}) {
  return (
    <div className="rounded-lg border border-border bg-background/60 p-3">
      <div className="text-[10px] uppercase tracking-widest text-muted-foreground">
        {symbol}
      </div>
      <div className="mt-1 font-mono text-lg font-semibold text-foreground">
        {loading
          ? "…"
          : value === null
          ? "—"
          : formatAmount(value, decimals, display)}
      </div>
    </div>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-mono text-foreground/90">{value}</span>
    </div>
  );
}

function StatusPill({ active }: { active: boolean }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-semibold tracking-widest ${
        active
          ? "bg-success/15 text-success"
          : "bg-muted text-muted-foreground"
      }`}
    >
      <span className="relative flex h-1.5 w-1.5">
        <span
          className={`absolute inline-flex h-full w-full rounded-full ${
            active ? "bg-success" : "bg-muted-foreground"
          } opacity-75 ${active ? "animate-ping" : ""}`}
        />
        <span
          className={`relative inline-flex rounded-full h-1.5 w-1.5 ${
            active ? "bg-success" : "bg-muted-foreground"
          }`}
        />
      </span>
      {active ? "ACTIVE" : "INACTIVE"}
    </span>
  );
}