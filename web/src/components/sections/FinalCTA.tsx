import { MonitorDown } from "lucide-react";
import Aurora from "@/components/bits/Aurora";
import ClickSpark from "@/components/bits/ClickSpark";
import ScrollFloat from "@/components/bits/ScrollFloat";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

interface FinalCTAProps {
  downloadUrl: string;
  version: string;
}

export default function FinalCTA({ downloadUrl, version }: FinalCTAProps) {
  return (
    <section id="download" className="border-t border-border py-28 md:py-32">
      <div className="container-app">
        <ScrollFloat>
          <div
            className="relative isolate overflow-hidden rounded-lg border border-border bg-bg-elev p-10 md:p-14"
            style={{ boxShadow: "var(--shadow-card)" }}
          >
            <Aurora
              className="opacity-[0.35]"
              colorStops={["#0a0b09", "#274a3a", "#8de8b9"]}
              amplitude={0.7}
              blend={0.45}
              speed={0.75}
            />
            <div
              aria-hidden
              className="absolute inset-0 -z-[1] bg-gradient-to-t from-bg-elev via-bg-elev/70 to-transparent"
            />

            <div className="relative grid items-center gap-10 md:grid-cols-[1.1fr_0.9fr] md:gap-14">
              <div>
                <Badge variant="accent" className="mb-5">
                  Ping {version}
                </Badge>
                <h2 className="text-balance text-[clamp(2.2rem,5vw,4rem)] leading-[1.05]">
                  2초면 충분합니다.
                </h2>
                <p className="mt-5 max-w-md text-muted">
                  Mac에 Ping을 설치하고, Option+P 한 번으로 작은 신호를
                  보내보세요.
                </p>
              </div>

              <div className="flex flex-col items-stretch gap-3 md:items-end">
                <ClickSpark>
                  <a
                    href={downloadUrl}
                    aria-label={`Ping ${version} DMG 다운로드`}
                  >
                    <Button variant="primary" size="lg" className="w-full md:w-auto">
                      <MonitorDown aria-hidden className="h-[18px] w-[18px]" />
                      Ping {version} 다운로드
                    </Button>
                  </a>
                </ClickSpark>
                <p className="text-xs text-subtle md:text-right">
                  Apple Silicon · macOS 26 Tahoe+ · ~24MB
                </p>
              </div>
            </div>
          </div>
        </ScrollFloat>
      </div>
    </section>
  );
}
