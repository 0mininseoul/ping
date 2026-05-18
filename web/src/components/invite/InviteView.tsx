import { ArrowDown, Download, ExternalLink } from "lucide-react";
import Aurora from "@/components/bits/Aurora";
import ClickSpark from "@/components/bits/ClickSpark";
import SplitText from "@/components/bits/SplitText";
import { Badge } from "@/components/ui/badge";
import BrandMark from "@/components/ui/brand-mark";
import { Button } from "@/components/ui/button";
import TokenChip from "./TokenChip";
import InviteSteps from "./InviteSteps";

interface InviteViewProps {
  token: string;
  downloadUrl: string;
  version: string;
}

export default function InviteView({
  token,
  downloadUrl,
  version,
}: InviteViewProps) {
  const deepLink = `ping://invite/${encodeURIComponent(token)}`;
  return (
    <main className="relative isolate min-h-screen overflow-hidden">
      <Aurora
        className="opacity-30"
        colorStops={["#f7f4ea", "#cfe9d8", "#8de8b9"]}
        amplitude={0.55}
        blend={0.35}
        speed={0.6}
      />
      <div
        aria-hidden
        className="absolute inset-0 bg-gradient-to-b from-bg/40 via-bg/70 to-bg"
      />

      <div className="container-app relative z-10 flex min-h-screen flex-col py-10">
        <a
          href="/"
          aria-label="Ping 홈으로"
          className="inline-flex w-fit items-center gap-2.5"
        >
          <BrandMark size={32} />
          <span className="font-bold">Ping</span>
        </a>

        <div className="my-auto grid items-center gap-12 py-16 md:grid-cols-[1.1fr_0.9fr] md:gap-16">
          <div>
            <Badge variant="accent" className="mb-6">
              초대장
            </Badge>
            <h1 className="text-balance text-[clamp(2.4rem,5.6vw,4.6rem)] leading-[1.04]">
              <SplitText as="span" text="초대장이 도착했어요." className="block" />
            </h1>
            <p className="mt-5 max-w-md text-base text-muted md:text-lg">
              Ping을 설치하고 아래 코드를 앱 안에 붙여 넣으면, 같은 방에서
              2초짜리 신호를 주고받을 수 있어요.
            </p>

            <div className="mt-8 max-w-xl space-y-3">
              <p className="text-xs font-bold uppercase tracking-[0.08em] text-subtle">
                초대 토큰
              </p>
              <TokenChip token={token} />
            </div>

            <div className="mt-8 flex flex-wrap items-center gap-3">
              <ClickSpark>
                <a href={deepLink} aria-label="Ping 앱에서 초대 열기">
                  <Button variant="primary" size="lg">
                    <ExternalLink aria-hidden className="h-[18px] w-[18px]" />
                    Ping 앱에서 열기
                  </Button>
                </a>
              </ClickSpark>
              <a href={downloadUrl} aria-label={`Ping ${version} 다운로드`}>
                <Button variant="secondary" size="lg">
                  <Download aria-hidden className="h-4 w-4" />
                  앱 설치하기
                </Button>
              </a>
              <a href="#how">
                <Button variant="ghost" size="lg">
                  참여 방법 보기
                  <ArrowDown aria-hidden className="h-4 w-4" />
                </Button>
              </a>
            </div>
          </div>

          <div id="how" className="md:pl-4">
            <p className="mb-4 text-xs font-bold uppercase tracking-[0.08em] text-accent">
              참여 방법
            </p>
            <InviteSteps />
            <p className="mt-6 text-xs text-subtle">
              토큰은 한 번만 사용할 수 있어요. 앱을 처음 열었다면 이 페이지를
              열어둔 채로 진행하세요.
            </p>
          </div>
        </div>

        <footer className="mt-auto border-t border-border pt-6 text-xs text-subtle">
          <div className="flex items-center justify-between">
            <span>
              Ping <span className="font-mono">{version}</span>
            </span>
            <span>macOS 13 Ventura 이상 · Apple Silicon Mac 권장</span>
          </div>
        </footer>
      </div>
    </main>
  );
}
