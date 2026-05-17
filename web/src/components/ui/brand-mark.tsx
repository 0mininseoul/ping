import { cn } from "@/lib/utils";

interface BrandMarkProps {
  size?: number;
  className?: string;
  alt?: string;
}

export default function BrandMark({
  size = 32,
  className,
  alt = "Ping 앱 아이콘",
}: BrandMarkProps) {
  return (
    <img
      src="/app-icon.png"
      alt={alt}
      width={size}
      height={size}
      className={cn("rounded-[22%] object-cover", className)}
      style={{ width: size, height: size }}
      decoding="async"
    />
  );
}
