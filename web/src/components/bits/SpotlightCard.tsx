import { type ReactNode, useRef, type MouseEvent } from "react";
import { cn } from "@/lib/utils";

interface SpotlightCardProps {
  children: ReactNode;
  className?: string;
  spotlightColor?: string;
}

export default function SpotlightCard({
  children,
  className,
  spotlightColor = "rgba(141, 232, 185, 0.18)",
}: SpotlightCardProps) {
  const ref = useRef<HTMLDivElement | null>(null);

  const handleMouseMove = (e: MouseEvent<HTMLDivElement>) => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    el.style.setProperty("--mx", `${e.clientX - rect.left}px`);
    el.style.setProperty("--my", `${e.clientY - rect.top}px`);
  };

  return (
    <div
      ref={ref}
      onMouseMove={handleMouseMove}
      className={cn(
        "group relative overflow-hidden rounded-lg border border-border bg-white/[0.04] p-6 transition-colors hover:border-white/20",
        className,
      )}
      style={{
        backgroundImage: `radial-gradient(360px circle at var(--mx, -200px) var(--my, -200px), ${spotlightColor}, transparent 60%)`,
      }}
    >
      <div className="relative z-10">{children}</div>
    </div>
  );
}
