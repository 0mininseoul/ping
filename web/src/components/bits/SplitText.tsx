import { motion, useReducedMotion } from "motion/react";
import { cn } from "@/lib/utils";

interface SplitTextProps {
  text: string;
  className?: string;
  delay?: number;
  stagger?: number;
  as?: "h1" | "h2" | "h3" | "p" | "span";
}

export default function SplitText({
  text,
  className,
  delay = 0,
  stagger = 0.04,
  as = "h1",
}: SplitTextProps) {
  const reduced = useReducedMotion();
  const Tag = motion[as] as typeof motion.h1;

  if (reduced) {
    const Static = as;
    return <Static className={className}>{text}</Static>;
  }

  const words = text.split(/(\s+)/);

  return (
    <Tag
      className={cn(className)}
      initial="hidden"
      animate="show"
      transition={{ staggerChildren: stagger, delayChildren: delay }}
      variants={{ hidden: {}, show: {} }}
      aria-label={text}
    >
      {words.map((word, wi) => {
        if (/^\s+$/.test(word)) {
          return (
            <span key={`s-${wi}`} aria-hidden>
              {word}
            </span>
          );
        }
        return (
          <span
            key={`w-${wi}`}
            aria-hidden
            className="inline-block whitespace-nowrap align-baseline"
          >
            {Array.from(word).map((ch, i) => (
              <motion.span
                key={`${wi}-${i}`}
                className="inline-block will-change-transform"
                variants={{
                  hidden: { y: "0.5em", opacity: 0, filter: "blur(8px)" },
                  show: {
                    y: 0,
                    opacity: 1,
                    filter: "blur(0px)",
                    transition: {
                      duration: 0.55,
                      ease: [0.22, 1, 0.36, 1],
                    },
                  },
                }}
              >
                {ch}
              </motion.span>
            ))}
          </span>
        );
      })}
    </Tag>
  );
}
