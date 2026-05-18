import ScrollFloat from "@/components/bits/ScrollFloat";
import BrandMark from "@/components/ui/brand-mark";

const beats = [
  {
    n: "01",
    title: "불러오기",
    body: "메뉴바의 Ping을 Option+P로 깨우면, 데스크탑 위에 원형 거울이 떠오릅니다.",
    visual: <BeatDesktop />,
  },
  {
    n: "02",
    title: "위치 정하기",
    body: "원하는 위치로 거울을 끌어다 놓으세요. 상대방도 같은 자리에서 신호를 받습니다.",
    visual: <BeatMirror />,
  },
  {
    n: "03",
    title: "2초 보내기",
    body: "Enter 한 번이면 끝. 정확히 2초가 지나면 영상이 사라지고 상대에게 전달됩니다.",
    visual: <BeatCountdown />,
  },
];

export default function DemoStrip() {
  return (
    <section
      id="flow"
      className="relative isolate border-t border-border py-28 md:py-36"
    >
      <div className="container-app">
        <ScrollFloat className="mb-14 max-w-2xl">
          <p className="mb-3 text-xs font-bold uppercase tracking-[0.12em] text-accent">
            FLOW
          </p>
          <h2 className="text-balance text-[clamp(2rem,4.4vw,3.6rem)] leading-[1.05]">
            Option+P{" "}
            <span className="text-muted">→</span> 2초{" "}
            <span className="text-muted">→</span> 끝.
          </h2>
          <p className="mt-4 max-w-xl text-muted">
            설명보다 빠르게 도착하는 작은 신호. 세 컷이면 충분합니다.
          </p>
        </ScrollFloat>

        <div className="grid gap-5 md:grid-cols-3">
          {beats.map((b, i) => (
            <ScrollFloat key={b.n} delay={i * 0.08}>
              <article className="flex h-full flex-col overflow-hidden rounded-lg border border-border bg-bg-elev">
                <div className="relative aspect-[4/3] w-full overflow-hidden border-b border-border bg-bg-elev">
                  {b.visual}
                </div>
                <div className="flex flex-1 flex-col p-6">
                  <span className="mb-2 font-mono text-xs text-subtle">
                    {b.n}
                  </span>
                  <h3 className="mb-2 text-xl">{b.title}</h3>
                  <p className="text-sm leading-relaxed text-muted">
                    {b.body}
                  </p>
                </div>
              </article>
            </ScrollFloat>
          ))}
        </div>
      </div>
    </section>
  );
}

function BeatDesktop() {
  return (
    <div className="absolute inset-0" aria-hidden>
      <div className="absolute inset-x-0 top-0 flex h-6 items-center gap-3 border-b border-border bg-fg/5 px-3 text-[10px] text-subtle">
        <span></span>
        <span className="ml-auto flex items-center gap-1.5 font-mono">
          <BrandMark
            size={14}
            className="rounded-[30%] shadow-[0_0_8px_rgba(141,232,185,0.55)]"
          />
          <span>10:24</span>
          <span>100%</span>
        </span>
      </div>
      <div className="absolute left-6 top-12 h-12 w-12 rounded-md border border-border bg-fg/5" />
      <div className="absolute left-6 top-28 h-12 w-12 rounded-md border border-border bg-fg/5" />
      <div className="absolute right-6 bottom-6 h-16 w-24 rounded-md border border-border bg-fg/5" />
      <div className="absolute left-1/2 top-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent shadow-[0_0_24px_var(--color-accent)]" />
    </div>
  );
}

function BeatMirror() {
  return (
    <div className="absolute inset-0 grid place-items-center" aria-hidden>
      <div
        className="relative grid h-3/5 w-3/5 place-items-center rounded-full border border-fg/15 bg-bg-elev/85 backdrop-blur-2xl"
        style={{
          boxShadow:
            "0 18px 60px rgba(47,170,110,0.18), inset 0 1px 22px rgba(255,255,255,0.7)",
        }}
      >
        <span className="font-mono text-xs text-fg/80">Move me</span>
        <span className="absolute -top-1 left-1/2 h-1.5 w-1.5 -translate-x-1/2 rounded-full bg-[color:var(--color-record)] shadow-[0_0_12px_var(--color-record)]" />
      </div>
      <span
        aria-hidden
        className="absolute right-[18%] top-[22%] h-2 w-2 rounded-full bg-accent/70"
      />
    </div>
  );
}

function BeatCountdown() {
  const r = 38;
  const c = 2 * Math.PI * r;
  return (
    <div className="absolute inset-0 grid place-items-center" aria-hidden>
      <svg
        viewBox="0 0 100 100"
        className="h-3/5 w-3/5 -rotate-90"
        role="img"
      >
        <circle cx="50" cy="50" r={r} stroke="rgba(10,11,9,0.12)" strokeWidth="3" fill="none" />
        <circle
          cx="50"
          cy="50"
          r={r}
          stroke="var(--color-record)"
          strokeWidth="3"
          fill="none"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * 0.32}
          style={{ filter: "drop-shadow(0 0 6px var(--color-record))" }}
        />
      </svg>
      <span className="absolute font-mono text-3xl font-bold text-fg">
        2.0
      </span>
      <span className="absolute bottom-5 left-1/2 -translate-x-1/2 rounded border border-border bg-fg/5 px-2.5 py-1 font-mono text-[10px] text-subtle">
        Enter
      </span>
    </div>
  );
}
