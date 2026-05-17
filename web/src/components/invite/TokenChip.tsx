import { useState } from "react";
import { Check, Copy } from "lucide-react";
import ClickSpark from "@/components/bits/ClickSpark";
import { cn } from "@/lib/utils";

interface TokenChipProps {
  token: string;
}

export default function TokenChip({ token }: TokenChipProps) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* ignore */
    }
  };

  return (
    <ClickSpark>
      <button
        type="button"
        onClick={copy}
        className={cn(
          "group flex w-full items-center justify-between gap-4 rounded-md border border-border bg-white/[0.04] p-4 text-left font-mono text-fg transition-colors hover:border-white/20",
          copied && "border-accent/60",
        )}
        aria-label={`초대 토큰 ${token} 복사`}
      >
        <span className="block min-w-0 flex-1 truncate text-base font-bold tracking-wide md:text-lg">
          {token}
        </span>
        <span
          className={cn(
            "inline-flex shrink-0 items-center gap-1.5 rounded-pill border px-2.5 py-1 text-xs",
            copied
              ? "border-accent/40 bg-accent/10 text-accent"
              : "border-border bg-white/[0.05] text-muted",
          )}
        >
          {copied ? (
            <>
              <Check aria-hidden className="h-3.5 w-3.5" />
              복사됨
            </>
          ) : (
            <>
              <Copy aria-hidden className="h-3.5 w-3.5" />
              복사
            </>
          )}
        </span>
      </button>
    </ClickSpark>
  );
}
