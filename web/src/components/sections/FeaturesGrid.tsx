import { Camera, Keyboard, Timer, Users } from "lucide-react";
import ScrollFloat from "@/components/bits/ScrollFloat";
import SpotlightCard from "@/components/bits/SpotlightCard";
import Orb from "@/components/bits/Orb";

interface Feature {
  icon: React.ReactNode;
  title: string;
  body: string;
  aside: string;
  visual?: React.ReactNode;
}

export default function FeaturesGrid() {
  const features: Feature[] = [
    {
      icon: <Camera aria-hidden className="h-5 w-5" />,
      title: "원형 거울 카메라",
      body: "사각 프레임 대신 원형. 어디에 두든 데스크탑에 어색하지 않게 녹아듭니다.",
      aside: "WebGL 셰이더 기반의 부드러운 가장자리",
      visual: (
        <div className="relative aspect-square w-full overflow-hidden rounded-md [mask-image:radial-gradient(circle,black_60%,transparent_72%)]">
          <Orb hue={142} hoverIntensity={0.32} backgroundColor="#f7f4ea" />
        </div>
      ),
    },
    {
      icon: <Keyboard aria-hidden className="h-5 w-5" />,
      title: "Option + P / L 단축키",
      body: "어떤 앱에 있든 얼굴만 보내거나 화면과 얼굴을 함께 보낼 수 있습니다.",
      aside: "전역 단축키 · 메뉴바 상주",
      visual: <KeycapVisual />,
    },
    {
      icon: <Timer aria-hidden className="h-5 w-5" />,
      title: "정확히 3초",
      body: "녹화는 0.0초에서 3.0초까지. 리뷰 화면에서 확인한 뒤 전송합니다.",
      aside: "송신 후 자동으로 만료",
      visual: <CountdownVisual />,
    },
    {
      icon: <Users aria-hidden className="h-5 w-5" />,
      title: "방 단위 공유",
      body: "초대 링크로 같은 방에 들어온 사람끼리만 Ping이 오갑니다. 기록은 내 룸에서 다시 볼 수 있습니다.",
      aside: "비공개 룸 · 초대 링크",
      visual: <RoomVisual />,
    },
  ];

  return (
    <section
      id="features"
      className="relative border-t border-border py-28 md:py-36"
    >
      <div className="container-app">
        <ScrollFloat className="mb-14 max-w-2xl">
          <p className="mb-3 text-xs font-bold uppercase tracking-[0.12em] text-accent">
            FEATURES
          </p>
          <h2 className="text-balance text-[clamp(2rem,4.4vw,3.6rem)] leading-[1.05]">
            언제 어디서든, 쉽고 빠르게.
          </h2>
        </ScrollFloat>

        <div className="grid gap-5 md:grid-cols-2">
          {features.map((f, i) => (
            <ScrollFloat key={f.title} delay={(i % 2) * 0.08}>
              <SpotlightCard className="flex h-full flex-col">
                <div className="mb-5 inline-flex h-9 w-9 items-center justify-center rounded-md border border-border bg-fg/5 text-accent">
                  {f.icon}
                </div>
                <h3 className="mb-2 text-2xl">{f.title}</h3>
                <p className="mb-5 text-muted">{f.body}</p>
                {f.visual ? (
                  <div className="mb-5 overflow-hidden rounded-md border border-border bg-bg-elev">
                    {f.visual}
                  </div>
                ) : null}
                <p className="mt-auto pt-2 text-xs font-medium uppercase tracking-[0.06em] text-subtle">
                  {f.aside}
                </p>
              </SpotlightCard>
            </ScrollFloat>
          ))}
        </div>
      </div>
    </section>
  );
}

function KeycapVisual() {
  return (
    <div className="grid aspect-[4/3] place-items-center bg-bg-elev">
      <div className="grid gap-3">
        <ShortcutRow keyLabel="P" caption="얼굴만" />
        <ShortcutRow keyLabel="L" caption="화면+얼굴" />
      </div>
    </div>
  );
}

function ShortcutRow({ keyLabel, caption }: { keyLabel: string; caption: string }) {
  return (
    <div className="flex items-center gap-3">
      <Keycap label="⌥" sub="Option" />
      <span className="pb-3 text-xl text-subtle">+</span>
      <Keycap label={keyLabel} />
      <span className="min-w-[4.5rem] text-xs font-medium text-muted">
        {caption}
      </span>
    </div>
  );
}

function Keycap({ label, sub }: { label: string; sub?: string }) {
  return (
    <div className="flex flex-col items-center gap-1.5" aria-label={sub ?? label}>
      <span className="grid h-12 w-12 place-items-center rounded-md border border-border bg-bg-elev font-mono text-xl font-bold text-fg shadow-[inset_0_-2px_0_rgba(10,11,9,0.12),0_4px_0_rgba(10,11,9,0.10)]">
        {label}
      </span>
      <span className="h-3 text-[10px] font-medium text-subtle">
        {sub ?? ""}
      </span>
    </div>
  );
}

function CountdownVisual() {
  return (
    <div className="relative grid aspect-[4/3] place-items-center bg-bg-elev">
      <div className="flex items-end gap-1.5">
        {Array.from({ length: 20 }).map((_, i) => (
          <span
            key={i}
            className="block w-1.5 rounded-full bg-accent/70"
            style={{
              height: `${20 + Math.sin((i / 20) * Math.PI) * 56}px`,
              opacity: i < 16 ? 1 : 0.25,
            }}
          />
        ))}
      </div>
      <span className="absolute right-4 top-3 font-mono text-xs text-subtle">
        00.0 → 03.0s
      </span>
    </div>
  );
}

function RoomVisual() {
  return (
    <div className="relative grid aspect-[4/3] place-items-center bg-bg-elev">
      <div className="flex -space-x-2.5">
        {["#8de8b9", "#f4ff78", "#ff6254", "#f7f4ea"].map((c, i) => (
          <span
            key={c}
            className="grid h-10 w-10 place-items-center rounded-full border-2 border-bg font-bold text-[#07100b]"
            style={{ background: c }}
          >
            {["A", "B", "C", "D"][i]}
          </span>
        ))}
      </div>
      <span className="absolute bottom-4 left-1/2 -translate-x-1/2 rounded-pill border border-border bg-fg/5 px-3 py-1 font-mono text-[10px] text-subtle">
        ROOM · friends
      </span>
    </div>
  );
}
