const steps = [
  { n: "1", label: "Ping 설치", body: "DMG로 빠르게 설치하세요." },
  { n: "2", label: "Ping 열기", body: "메뉴바에 P 마크가 떠 있는지 확인." },
  { n: "3", label: "토큰 입력", body: "룸 화면에서 위 토큰을 붙여 넣으세요." },
];

export default function InviteSteps() {
  return (
    <ol className="grid gap-3" aria-label="초대 참여 절차">
      {steps.map((s) => (
        <li
          key={s.n}
          className="flex items-start gap-4 rounded-md border border-border bg-white/[0.03] p-4"
        >
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-accent/40 bg-accent/10 font-mono text-sm font-bold text-accent">
            {s.n}
          </span>
          <div>
            <p className="text-sm font-bold text-fg">{s.label}</p>
            <p className="mt-0.5 text-sm text-muted">{s.body}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}
