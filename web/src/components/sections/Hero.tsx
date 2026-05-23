import { ArrowDown, MonitorDown } from "lucide-react";
import Aurora from "@/components/bits/Aurora";
import SplitText from "@/components/bits/SplitText";
import ShinyText from "@/components/bits/ShinyText";
import Orb from "@/components/bits/Orb";
import ClickSpark from "@/components/bits/ClickSpark";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import BrandMark from "@/components/ui/brand-mark";

interface HeroProps {
  downloadUrl: string;
  version: string;
}

export default function Hero({ downloadUrl, version }: HeroProps) {
  return (
    <section className="relative isolate overflow-hidden pt-32 pb-28 md:pt-44 md:pb-36">
      <Aurora
        className="opacity-[0.35]"
        colorStops={["#f7f4ea", "#cfe9d8", "#8de8b9"]}
        amplitude={0.7}
        blend={0.45}
        speed={0.9}
      />
      <div
        aria-hidden
        className="absolute inset-x-0 bottom-0 z-[1] h-64 bg-gradient-to-b from-transparent to-bg"
      />

      <div className="container-app relative z-10">
        <div className="grid items-center gap-12 md:grid-cols-[1.05fr_0.95fr] md:gap-14">
          <div>
            <div className="mb-7 inline-flex items-center gap-2 rounded-pill border border-border bg-bg-elev px-3 py-1.5 text-xs text-muted backdrop-blur-md">
              <BrandMark size={16} className="rounded-[28%]" />
              <span className="font-medium text-fg">Ping</span>
              <span className="text-faint">·</span>
              <span className="font-mono tracking-tight">Option + P / L</span>
            </div>

            <h1 className="mb-5 overflow-visible pb-[0.05em] text-balance text-[clamp(2.6rem,6.2vw,5.4rem)] font-bold leading-[1.1]">
              <SplitText
                as="span"
                text="보고 싶을 때,"
                className="block"
              />
              <span className="block">
                <ShinyText
                  text="Ping하세요."
                  color="#0a0b09"
                  shineColor="#2faa6e"
                  speed={3.2}
                />
              </span>
            </h1>

            <p className="mb-9 max-w-[36rem] text-balance text-base leading-relaxed text-muted md:text-lg">
              Ping은 Option+P로 얼굴 거울을, Option+L로 화면+얼굴 거울을
              열고, 3초짜리 영상 메시지를 리뷰 후 보내는 작은 Mac 앱입니다.
            </p>

            <div className="mb-10 flex flex-wrap items-center gap-3">
              <ClickSpark>
                <a href={downloadUrl} aria-label={`Ping ${version} 다운로드`}>
                  <Button variant="primary" size="lg">
                    <MonitorDown aria-hidden className="h-[18px] w-[18px]" />
                    Ping {version} 다운로드
                  </Button>
                </a>
              </ClickSpark>
              <a href="#flow">
                <Button variant="secondary" size="lg">
                  작동 방식 보기
                  <ArrowDown aria-hidden className="h-4 w-4" />
                </Button>
              </a>
            </div>

            <dl
              className="grid max-w-[34rem] grid-cols-3 gap-x-6 border-t border-border pt-5"
              aria-label="Ping 요약"
            >
              <FactItem term="단축키" value="Option + P/L" />
              <FactItem term="길이" value="정확히 3초" />
              <FactItem term="배포" value="DMG 설치" />
            </dl>
          </div>

          <div
            className="relative mx-auto aspect-square w-full max-w-[440px]"
            aria-hidden
          >
            <div className="absolute inset-0 [mask-image:radial-gradient(circle,black_55%,transparent_72%)]">
              <Orb hue={142} hoverIntensity={0.36} backgroundColor="#f7f4ea" />
            </div>
            <MirrorPreview />
            <Badge
              variant="record"
              className="absolute left-1/2 top-3 -translate-x-1/2"
            >
              <span className="block h-1.5 w-1.5 rounded-full bg-[color:var(--color-record)] shadow-[0_0_8px_var(--color-record)]" />
              REC · 3.0s
            </Badge>
          </div>
        </div>
      </div>
    </section>
  );
}

function FactItem({ term, value }: { term: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-[0.06em] text-subtle">
        {term}
      </dt>
      <dd className="mt-1.5 text-base font-bold text-fg">{value}</dd>
    </div>
  );
}

function MirrorPreview() {
  return (
    <div
      className="absolute left-1/2 top-1/2 grid aspect-square w-[40%] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border border-fg/15 bg-bg-elev/80 text-sm font-bold text-fg backdrop-blur-2xl"
      style={{
        boxShadow:
          "inset 0 1px 22px rgba(255,255,255,0.6), 0 18px 42px rgba(10,11,9,0.14)",
      }}
    >
      <span className="font-mono tracking-tight">Option+P/L</span>
      <span
        aria-hidden
        className="absolute top-4 h-2 w-2 rounded-full bg-[color:var(--color-record)] shadow-[0_0_18px_rgba(255,90,71,0.55)]"
      />
    </div>
  );
}
