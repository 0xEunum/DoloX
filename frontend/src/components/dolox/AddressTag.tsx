import { useState } from "react";
import { Copy, Check, ExternalLink } from "lucide-react";
import { copyToClipboard, truncateAddress } from "@/lib/dolox/utils";
import { EXPLORER } from "@/lib/dolox/chain";

interface Props {
  address: string;
  type?: "address" | "tx";
  className?: string;
  showCopy?: boolean;
  showExplorer?: boolean;
}

export function AddressTag({
  address,
  type = "address",
  className = "",
  showCopy = true,
  showExplorer = true,
}: Props) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    const ok = await copyToClipboard(address);
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    }
  };

  const url =
    type === "tx" ? `${EXPLORER}/tx/${address}` : `${EXPLORER}/address/${address}`;

  return (
    <span
      className={`inline-flex items-center gap-1.5 font-mono text-xs ${className}`}
    >
      <span className="text-foreground/80">{truncateAddress(address)}</span>
      {showCopy && (
        <button
          onClick={handleCopy}
          className="text-muted-foreground hover:text-primary transition-colors relative"
          aria-label="Copy address"
        >
          {copied ? (
            <Check className="h-3 w-3 text-success" />
          ) : (
            <Copy className="h-3 w-3" />
          )}
          {copied && (
            <span className="absolute -top-7 left-1/2 -translate-x-1/2 rounded bg-secondary px-2 py-0.5 text-[10px] text-foreground border border-border">
              Copied!
            </span>
          )}
        </button>
      )}
      {showExplorer && (
        <a
          href={url}
          target="_blank"
          rel="noreferrer noopener"
          className="text-muted-foreground hover:text-primary transition-colors"
          aria-label="Open in explorer"
        >
          <ExternalLink className="h-3 w-3" />
        </a>
      )}
    </span>
  );
}