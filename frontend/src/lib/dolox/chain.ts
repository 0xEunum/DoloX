import { createPublicClient, http } from "viem";
import { baseSepolia } from "viem/chains";

export const EXPLORER = "https://sepolia.basescan.org";

export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http("https://base-testnet.api.pocket.network"),
});

// Loosely typed alias to sidestep viem's overly strict
// `authorizationList`-required readContract parameter typing.
// All calls remain runtime-safe; we only relax compile-time checks.
export const readClient = publicClient as unknown as {
  readContract: (args: any) => Promise<any>;
  getLogs: (args: any) => Promise<any[]>;
  getBlock: (args?: any) => Promise<any>;
  multicall: (args: any) => Promise<any[]>;
};

export async function getRecentFromBlock(
  blocksBack = 25_000n,
): Promise<bigint> {
  const block = await publicClient.getBlockNumber();
  return block > blocksBack ? block - blocksBack : 0n;
}
