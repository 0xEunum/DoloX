import { useEffect, useState } from "react";
import { Zap, AlertCircle } from "lucide-react";
import { getRecentFromBlock, readClient } from "@/lib/dolox/chain";
import { ADDRESSES, ERC20_ABI } from "@/lib/dolox/contracts";
import { AddressTag } from "./AddressTag";
import { formatAmount, formatRelativeTime } from "@/lib/dolox/utils";
import { parseAbiItem } from "viem";

interface Payment {
  txHash: string;
  from: string;
  value: bigint;
  blockNumber: bigint;
  timestamp: number;
}

const TRANSFER_EVENT = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)",
);

export function PaymentFeed() {
  const [items, setItems] = useState<Payment[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchPayments = async () => {
    setError(null);
    const fromBlock = await getRecentFromBlock();
    try {
      const logs = await readClient.getLogs({
        address: ADDRESSES.MOCK_USDC,
        event: TRANSFER_EVENT,
        fromBlock,
        toBlock: "latest",
      });
      const filtered = (logs as any[]).filter(
        (l) =>
          l.args.to?.toLowerCase() ===
          ADDRESSES.SIGNAL_AGENT_ACCOUNT.toLowerCase(),
      );
      const last10 = filtered
        .sort((a, b) => Number(b.blockNumber - a.blockNumber))
        .slice(0, 10);

      const blocks = await Promise.all(
        last10.map((l) => readClient.getBlock({ blockNumber: l.blockNumber })),
      );

      const payments: Payment[] = last10.map((l, i) => ({
        txHash: l.transactionHash,
        from: l.args.from,
        value: l.args.value as bigint,
        blockNumber: l.blockNumber,
        timestamp: Number(blocks[i].timestamp),
      }));
      setItems(payments);
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Failed to fetch payments");
      setItems(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPayments();
    const i = setInterval(fetchPayments, 30_000);
    return () => clearInterval(i);
  }, []);

  return (
    <Panel
      title="x402 Agent Payments"
      icon={<Zap className="w-4 h-4 text-primary" />}
      accent="primary"
    >
      {loading && !items ? (
        <Skeleton rows={3} />
      ) : error ? (
        <ErrorRow message={error} onRetry={fetchPayments} />
      ) : !items || items.length === 0 ? (
        <Empty text="No payments yet — start the keeper to begin" />
      ) : (
        <ul className="divide-y divide-border">
          {items.map((p) => (
            <li
              key={p.txHash}
              className="flex items-center justify-between gap-3 py-2.5 pl-3 border-l-2 border-primary/60"
            >
              <div className="flex items-center gap-2 min-w-0">
                <span aria-hidden>⚡</span>
                <span className="text-sm truncate">
                  Exec Agent paid{" "}
                  <span className="font-mono text-primary">
                    {formatAmount(p.value, 6, 3)} USDC
                  </span>{" "}
                  to Signal Agent
                </span>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                <AddressTag address={p.txHash} type="tx" showCopy={false} />
                <span className="font-mono text-[11px] text-muted-foreground w-20 text-right">
                  {formatRelativeTime(p.timestamp)}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

export function Panel({
  title,
  icon,
  accent,
  children,
  headerExtra,
}: {
  title: string;
  icon: React.ReactNode;
  accent: "primary" | "success" | "warning";
  children: React.ReactNode;
  headerExtra?: React.ReactNode;
}) {
  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <div className="flex items-center justify-between gap-3 px-4 sm:px-5 py-3 border-b border-border bg-background/40">
        <div className="flex items-center gap-2">
          {icon}
          <h3 className="font-semibold text-sm">{title}</h3>
        </div>
        {headerExtra}
      </div>
      <div className="p-4 sm:p-5">{children}</div>
    </section>
  );
}

function Skeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-2">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="h-9 rounded bg-secondary/60 animate-pulse" />
      ))}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <div className="py-8 text-center text-sm text-muted-foreground italic">
      {text}
    </div>
  );
}

function ErrorRow({
  message,
  onRetry,
}: {
  message: string;
  onRetry: () => void;
}) {
  return (
    <div className="flex items-center gap-2 rounded border border-destructive/30 bg-destructive/10 px-3 py-2 text-xs text-destructive">
      <AlertCircle className="w-3.5 h-3.5" />
      <span className="flex-1 truncate">{message}</span>
      <button
        onClick={onRetry}
        className="font-semibold underline-offset-2 hover:underline"
      >
        Retry
      </button>
    </div>
  );
}

export { Skeleton, Empty, ErrorRow };
