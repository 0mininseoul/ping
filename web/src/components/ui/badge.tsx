import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1.5 rounded-pill border px-3 py-1 text-xs font-bold uppercase tracking-[0.08em]",
  {
    variants: {
      variant: {
        default:
          "border-border bg-bg-elev text-fg",
        accent:
          "border-accent/40 bg-accent/10 text-accent",
        record:
          "border-[color:var(--color-record)]/40 bg-[color:var(--color-record)]/10 text-[color:var(--color-record)]",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
