import { useEffect, useState } from "react";
import { Droplets } from "lucide-react";
import { readClient } from "@/lib/dolox/chain";
import { ADDRESSES, ERC20_ABI } from "@/lib/dolox/contracts";
import { AddressTag } from "./AddressTag";
import { formatAmount } from "@/lib/dolox/utils";
import { ErrorRow, Panel, Skeleton } from "./PaymentFeed";

export function PoolStatus() {
  const [weth, setWeth] = useState<bigint | null>(null);
  const [usdc, setUsdc] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAll = async () => {
    setError(null);
    try {
      const [w, u] = await Promise.all([
        readClient.readContract({
          address: ADDRESSES.WETH,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: [ADDRESSES.DOLOX_POOL],
        }),
        readClient.readContract({
          address: ADDRESSES.MOCK_USDC,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: [ADDRESSES.DOLOX_POOL],
        }),
      ]);
      setWeth(w as bigint);
      setUsdc(u as bigint);
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Failed to fetch pool");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAll();
    const i = setInterval(fetchAll, 30_000);
    return () => clearInterval(i);
  }, []);

  return (
    <Panel
      title="DoloX Liquidity Pool"
      icon={<Droplets className="w-4 h-4 text-primary" />}
      accent="primary"
      headerExtra={<AddressTag address={ADDRESSES.DOLOX_POOL} />}
    >
      {loading ? (
        <Skeleton rows={1} />
      ) : error ? (
        <ErrorRow message={error} onRetry={fetchAll} />
      ) : (
        <div className="flex items-end justify-between gap-3 flex-wrap">
          <div className="font-mono text-2xl">
            <span className="text-foreground">
              {formatAmount(weth, 18, 4)}
            </span>
            <span className="text-muted-foreground text-sm"> WETH</span>
            <span className="text-muted-foreground"> / </span>
            <span className="text-foreground">
              {formatAmount(usdc, 6, 2)}
            </span>
            <span className="text-muted-foreground text-sm"> USDC</span>
          </div>
          <span className="text-[11px] uppercase tracking-widest text-muted-foreground">
            Uniswap V3 · 0.3% fee tier
          </span>
        </div>
      )}
    </Panel>
  );
}