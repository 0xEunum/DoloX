import { useEffect, useState } from "react";
import { ArrowLeftRight } from "lucide-react";
import { readClient, getRecentFromBlock } from "@/lib/dolox/chain";
import { ADDRESSES, SWAP_EXECUTOR_ABI } from "@/lib/dolox/contracts";
import { AddressTag } from "./AddressTag";
import { formatAmount, formatRelativeTime } from "@/lib/dolox/utils";
import { Empty, ErrorRow, Panel, Skeleton } from "./PaymentFeed";
import { parseAbiItem } from "viem";

interface SwapRow {
  txHash: string;
  amountIn: bigint;
  amountOut: bigint;
  timestamp: number;
}

const SWAP_EXECUTED_EVENT = parseAbiItem(
  "event SwapExecuted(address indexed agentAccount, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint24 fee, uint256 timestamp)",
);

export function SwapHistory() {
  const [items, setItems] = useState<SwapRow[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [totalIn, setTotalIn] = useState<bigint>(0n);

  const fetchSwaps = async () => {
    setError(null);
    try {
      const fromBlock = await getRecentFromBlock();
      const logs = await readClient.getLogs({
        address: ADDRESSES.SWAP_EXECUTOR,
        event: SWAP_EXECUTED_EVENT,
        fromBlock,
        toBlock: "latest",
      });
      const sorted = (logs as any[]).sort((a, b) =>
        Number(b.blockNumber - a.blockNumber),
      );
      let sum = 0n;
      for (const l of sorted) sum += l.args.amountIn as bigint;
      setTotalIn(sum);
      const last10 = sorted.slice(0, 10);
      const blocks = await Promise.all(
        last10.map((l) => readClient.getBlock({ blockNumber: l.blockNumber })),
      );
      const rows: SwapRow[] = last10.map((l, i) => ({
        txHash: l.transactionHash,
        amountIn: l.args.amountIn as bigint,
        amountOut: l.args.amountOut as bigint,
        timestamp: Number(blocks[i].timestamp),
      }));
      setItems(rows);
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Failed to fetch swaps");
      setItems(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSwaps();
    const i = setInterval(fetchSwaps, 30_000);
    return () => clearInterval(i);
  }, []);

  return (
    <Panel
      title="Swap Executions"
      icon={<ArrowLeftRight className="w-4 h-4 text-success" />}
      accent="success"
      headerExtra={
        <span className="font-mono text-[11px] text-muted-foreground">
          Vol:{" "}
          <span className="text-success">
            {formatAmount(totalIn, 18, 4)} WETH
          </span>
        </span>
      }
    >
      {loading && !items ? (
        <Skeleton rows={3} />
      ) : error ? (
        <ErrorRow message={error} onRetry={fetchSwaps} />
      ) : !items || items.length === 0 ? (
        <Empty text="No swaps yet" />
      ) : (
        <ul className="divide-y divide-border">
          {items.map((s) => (
            <li
              key={s.txHash}
              className="flex items-center justify-between gap-3 py-2.5 pl-3 border-l-2 border-success/60"
            >
              <div className="flex items-center gap-2 min-w-0">
                <span aria-hidden>🔄</span>
                <span className="text-sm">
                  <span className="font-mono">
                    {formatAmount(s.amountIn, 18, 4)} WETH
                  </span>{" "}
                  →{" "}
                  <span className="font-mono text-success">
                    {formatAmount(s.amountOut, 6, 2)} USDC
                  </span>
                </span>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                <AddressTag address={s.txHash} type="tx" showCopy={false} />
                <span className="font-mono text-[11px] text-muted-foreground w-20 text-right">
                  {formatRelativeTime(s.timestamp)}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}
