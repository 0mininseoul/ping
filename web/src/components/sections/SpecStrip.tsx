import { Cpu, HardDrive, MonitorCog, ShieldCheck } from "lucide-react";
import ScrollFloat from "@/components/bits/ScrollFloat";

const specs = [
  { icon: <Cpu className="h-4 w-4" />, label: "Apple Silicon Mac 권장" },
  { icon: <MonitorCog className="h-4 w-4" />, label: "macOS 13 Ventura+" },
  { icon: <HardDrive className="h-4 w-4" />, label: "~24MB · DMG 설치" },
  { icon: <ShieldCheck className="h-4 w-4" />, label: "메뉴바에서만 동작" },
];

export default function SpecStrip() {
  return (
    <section className="border-t border-border py-14">
      <div className="container-app">
        <ScrollFloat>
          <ul className="grid grid-cols-2 gap-x-6 gap-y-4 md:grid-cols-4">
            {specs.map((s) => (
              <li
                key={s.label}
                className="flex items-center gap-2.5 text-sm text-muted"
              >
                <span className="grid h-7 w-7 place-items-center rounded-full border border-border bg-bg-elev text-accent">
                  {s.icon}
                </span>
                <span className="font-medium text-fg">{s.label}</span>
              </li>
            ))}
          </ul>
        </ScrollFloat>
      </div>
    </section>
  );
}
