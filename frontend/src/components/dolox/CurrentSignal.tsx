import { useEffect, useState } from "react";
import { Radio } from "lucide-react";
import { Panel } from "./PaymentFeed";
import { formatRelativeTime } from "@/lib/dolox/utils";

interface SignalPayload {
  action?: "BUY" | "SELL" | "HOLD" | string;
  price?: number;
  confidence?: number;
  source?: string;
  timestamp?: number;
  updatedAt?: number;
}

export function CurrentSignal() {
  const [data, setData] = useState<SignalPayload | null>(null);
  const [offline, setOffline] = useState(false);
  const [loading, setLoading] = useState(true);

  const fetchSignal = async () => {
    try {
      const res = await fetch("http://localhost:3001/v1/signal", {
        cache: "no-store",
      });
      if (!res.ok) throw new Error("bad status");
      const json = (await res.json()) as SignalPayload;
      setData(json);
      setOffline(false);
    } catch {
      setOffline(true);
      setData(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSignal();
    const i = setInterval(fetchSignal, 10_000);
    return () => clearInterval(i);
  }, []);

  const action = (data?.action || "").toUpperCase();
  const actionColor =
    action === "BUY"
      ? "bg-success/15 text-success border-success/30"
      : action === "SELL"
        ? "bg-destructive/15 text-destructive border-destructive/30"
        : "bg-muted text-muted-foreground border-border";

  const ts = data?.timestamp || data?.updatedAt;

  return (
    <Panel
      title="Current Signal"
      icon={<Radio className="w-4 h-4 text-primary" />}
      accent="primary"
      headerExtra={
        offline ? (
          <span className="text-[11px] uppercase tracking-widest text-muted-foreground">
            Keeper Offline
          </span>
        ) : (
          <span className="text-[11px] uppercase tracking-widest text-success">
            Live · 10s
          </span>
        )
      }
    >
      {loading ? (
        <div className="h-12 rounded bg-secondary/60 animate-pulse" />
      ) : offline ? (
        <div className="text-sm text-muted-foreground italic">
          Keeper Offline · waiting for{" "}
          <span className="font-mono">localhost:3001</span>
        </div>
      ) : (
        <div className="flex items-center gap-4 flex-wrap">
          <span
            className={`font-mono text-sm font-semibold px-3 py-1 rounded border ${actionColor}`}
          >
            {action || "—"}
          </span>
          <Item label="Price">
            <span className="font-mono text-foreground">
              {data?.price !== undefined
                ? `$${Number(data.price).toFixed(2)}`
                : "—"}
            </span>
          </Item>
          <Item label="Confidence">
            <span className="font-mono text-foreground">
              {data?.confidence !== undefined
                ? `${Math.round(Number(data.confidence) * 100)}%`
                : "—"}
            </span>
          </Item>
          <Item label="Source">
            <span className="font-mono text-foreground/80">
              {data?.source || "—"}
            </span>
          </Item>
          <Item label="Updated">
            <span className="font-mono text-foreground/80">
              {ts ? formatRelativeTime(ts) : "—"}
            </span>
          </Item>
        </div>
      )}
    </Panel>
  );
}

function Item({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col">
      <span className="text-[10px] uppercase tracking-widest text-muted-foreground">
        {label}
      </span>
      <span className="text-sm">{children}</span>
    </div>
  );
}
