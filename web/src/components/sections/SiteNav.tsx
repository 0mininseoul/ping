import { useEffect, useState } from "react";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import BrandMark from "@/components/ui/brand-mark";
import { cn } from "@/lib/utils";
import { useOS } from "@/lib/useOS";

interface SiteNavProps {
  macDownloadUrl: string;
  windowsDownloadUrl: string;
}

const links = [
  { href: "#flow", label: "작동 방식" },
  { href: "#features", label: "기능" },
  { href: "#download", label: "다운로드" },
];

export default function SiteNav({
  macDownloadUrl,
  windowsDownloadUrl,
}: SiteNavProps) {
  const [scrolled, setScrolled] = useState(false);
  const os = useOS();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const targets = [
    { key: "mac", url: macDownloadUrl, label: "macOS", short: "Mac", aria: "Download for macOS" },
    { key: "win", url: windowsDownloadUrl, label: "Windows", short: "Windows", aria: "Download for Windows" },
  ];
  const ordered = os === "windows" ? [targets[1], targets[0]] : targets;

  return (
    <header
      className={cn(
        "fixed inset-x-0 top-0 z-50 transition-all duration-300",
        scrolled
          ? "border-b border-border bg-bg/70 backdrop-blur-xl"
          : "bg-transparent",
      )}
    >
      <div className="container-app flex h-16 items-center justify-between">
        <a
          href="/"
          aria-label="Ping 홈"
          className="flex items-center gap-2.5"
        >
          <BrandMark size={32} className="shadow-[0_0_22px_rgba(47,170,110,0.14)]" />
          <span className="text-base font-bold tracking-tight">Ping</span>
        </a>

        <nav
          className="hidden items-center gap-7 text-sm text-muted md:flex"
          aria-label="페이지 내 이동"
        >
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="transition-colors hover:text-fg"
            >
              {l.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          {ordered.map((t, i) => (
            <a key={t.key} href={t.url} aria-label={t.aria}>
              <Button variant={i === 0 ? "primary" : "secondary"} size="sm">
                <Download aria-hidden className="h-4 w-4" />
                <span className="hidden sm:inline">{t.label}</span>
                <span className="sm:hidden">{t.short}</span>
              </Button>
            </a>
          ))}
        </div>
      </div>
    </header>
  );
}
