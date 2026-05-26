import { MonitorDown } from "lucide-react";
import ClickSpark from "@/components/bits/ClickSpark";
import ScrollFloat from "@/components/bits/ScrollFloat";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

interface FinalCTAProps {
  macDownloadUrl: string;
  windowsDownloadUrl: string;
  macVersion: string;
  windowsVersion: string;
}

export default function FinalCTA({
  macDownloadUrl,
  windowsDownloadUrl,
  macVersion,
  windowsVersion,
}: FinalCTAProps) {
  return (
    <section id="download" className="border-t border-border py-28 md:py-32">
      <div className="container-app">
        <ScrollFloat>
          <div
            className="relative overflow-hidden rounded-lg border border-[rgba(10,11,9,0.10)] bg-bg-elev p-10 shadow-[0_18px_42px_rgba(10,11,9,0.07)] md:p-14"
          >
            <div
              aria-hidden
              className="pointer-events-none absolute inset-px rounded-[23px] border border-white/70"
            />

            <div className="relative grid items-center gap-10 md:grid-cols-[1.1fr_0.9fr] md:gap-14">
              <div>
                <Badge variant="accent" className="mb-5">
                  macOS {macVersion} · Windows {windowsVersion}
                </Badge>
                <h2 className="text-balance text-[clamp(2.2rem,5vw,4rem)] leading-[1.05]">
                  3초면 충분합니다.
                </h2>
                <p className="mt-5 max-w-md text-muted">
                  Mac 또는 Windows에 Ping을 설치하고, 키보드 단축키로 작은
                  신호를 보내보세요.
                </p>
              </div>

              <div className="flex flex-col items-stretch gap-3 md:items-end">
                <ClickSpark>
                  <a
                    href={macDownloadUrl}
                    aria-label={`Ping ${macVersion} macOS DMG 다운로드`}
                  >
                    <Button
                      variant="primary"
                      size="lg"
                      className="w-full !shadow-[0_10px_22px_rgba(47,170,110,0.16)] md:w-auto"
                    >
                      <MonitorDown aria-hidden className="h-[18px] w-[18px]" />
                      Download for macOS
                    </Button>
                  </a>
                </ClickSpark>
                <ClickSpark>
                  <a
                    href={windowsDownloadUrl}
                    aria-label={`Ping ${windowsVersion} Windows EXE 다운로드`}
                  >
                    <Button
                      variant="secondary"
                      size="lg"
                      className="w-full md:w-auto"
                    >
                      <MonitorDown aria-hidden className="h-[18px] w-[18px]" />
                      Download for Windows
                    </Button>
                  </a>
                </ClickSpark>
                <p className="text-xs text-subtle md:text-right">
                  macOS 13 Ventura+ · Windows 11 24H2+ · Windows EXE는 무료
                  자체서명 배포라 SmartScreen 경고가 보일 수 있습니다.
                </p>
              </div>
            </div>
          </div>
        </ScrollFloat>
      </div>
    </section>
  );
}
