import { type ReactNode, useRef, type MouseEvent } from "react";
import { cn } from "@/lib/utils";

interface ClickSparkProps {
  children: ReactNode;
  className?: string;
  color?: string;
  count?: number;
}

export default function ClickSpark({
  children,
  className,
  color = "#8de8b9",
  count = 8,
}: ClickSparkProps) {
  const ref = useRef<HTMLSpanElement | null>(null);

  const onClick = (e: MouseEvent<HTMLSpanElement>) => {
    const host = ref.current;
    if (!host) return;
    if (
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }
    const rect = host.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    for (let i = 0; i < count; i++) {
      const dot = document.createElement("span");
      dot.style.cssText = `
        position: absolute;
        left: ${x}px;
        top: ${y}px;
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: ${color};
        pointer-events: none;
        transform: translate(-50%, -50%);
        opacity: 0.95;
        filter: drop-shadow(0 0 6px ${color});
      `;
      const angle = (i / count) * Math.PI * 2;
      const dist = 36 + Math.random() * 18;
      const dx = Math.cos(angle) * dist;
      const dy = Math.sin(angle) * dist;
      host.appendChild(dot);
      dot.animate(
        [
          { transform: "translate(-50%, -50%) scale(1)", opacity: 0.95 },
          {
            transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(0.2)`,
            opacity: 0,
          },
        ],
        { duration: 600, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
      );
      setTimeout(() => dot.remove(), 700);
    }
  };

  return (
    <span
      ref={ref}
      onClick={onClick}
      className={cn("relative inline-flex isolate", className)}
    >
      {children}
    </span>
  );
}
