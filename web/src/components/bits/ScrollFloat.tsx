import { type ReactNode, useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { cn } from "@/lib/utils";

interface ScrollFloatProps {
  children: ReactNode;
  className?: string;
  delay?: number;
  offsetY?: number;
  once?: boolean;
}

export default function ScrollFloat({
  children,
  className,
  delay = 0,
  offsetY = 28,
  once = true,
}: ScrollFloatProps) {
  const ref = useRef<HTMLDivElement | null>(null);
  const inView = useInView(ref, { once, amount: 0.15 });
  const reduced = useReducedMotion();

  return (
    <motion.div
      ref={ref}
      className={cn(className)}
      initial={reduced ? false : { y: offsetY }}
      animate={inView || reduced ? { y: 0 } : undefined}
      transition={{
        duration: 0.65,
        ease: [0.22, 1, 0.36, 1],
        delay,
      }}
    >
      {children}
    </motion.div>
  );
}
