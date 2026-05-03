import { Github, ExternalLink } from "lucide-react";

const BADGES = [
  "Base",
  "ERC-4337",
  "Basenames",
  "x402",
  "Uniswap V3",
];

export function Footer() {
  return (
    <footer className="border-t border-border mt-12">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 flex flex-col gap-5">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="text-sm text-muted-foreground">
            Built at{" "}
            <span className="text-foreground font-semibold">
              ETHGlobal OpenAgents 2026
            </span>
          </div>
          <nav className="flex flex-wrap items-center gap-4 text-xs">
            <FootLink
              href="https://github.com/0xEunum/dolox"
              icon={<Github className="w-3.5 h-3.5" />}
            >
              GitHub
            </FootLink>
            <FootLink
              href="https://sepolia.basescan.org"
              icon={<ExternalLink className="w-3.5 h-3.5" />}
            >
              Basescan
            </FootLink>
            <FootLink
              href="https://docs.pimlico.io/"
              icon={<ExternalLink className="w-3.5 h-3.5" />}
            >
              Pimlico Bundler
            </FootLink>
          </nav>
        </div>
        <div className="flex flex-wrap gap-2">
          {BADGES.map((b) => (
            <span
              key={b}
              className="font-mono text-[10px] uppercase tracking-widest border border-border bg-background/60 text-foreground/80 px-2 py-1 rounded"
            >
              {b}
            </span>
          ))}
        </div>
      </div>
    </footer>
  );
}

function FootLink({
  href,
  children,
  icon,
}: {
  href: string;
  children: React.ReactNode;
  icon?: React.ReactNode;
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer noopener"
      className="inline-flex items-center gap-1.5 text-muted-foreground hover:text-primary transition-colors"
    >
      {icon}
      {children}
    </a>
  );
}