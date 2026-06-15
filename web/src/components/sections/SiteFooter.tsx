import BrandMark from "@/components/ui/brand-mark";

interface SiteFooterProps {
  macVersion: string;
}

export default function SiteFooter({ macVersion }: SiteFooterProps) {
  return (
    <footer className="border-t border-border py-12">
      <div className="container-app flex flex-col items-start justify-between gap-6 md:flex-row md:items-center">
        <div className="flex items-center gap-2.5">
          <BrandMark size={28} />
          <span className="text-sm">
            <span className="font-bold">Ping</span>
            <span className="ml-2 font-mono text-subtle">
              macOS {macVersion}
            </span>
          </span>
        </div>

        <p className="text-xs text-subtle">
          macOS 13 Ventura+
        </p>

        <nav
          aria-label="푸터"
          className="flex items-center gap-5 text-xs text-muted"
        >
          <a href="#flow" className="hover:text-fg">
            작동 방식
          </a>
          <a href="#features" className="hover:text-fg">
            기능
          </a>
          <span className="text-faint">© 2026 Ping</span>
        </nav>
      </div>
    </footer>
  );
}
