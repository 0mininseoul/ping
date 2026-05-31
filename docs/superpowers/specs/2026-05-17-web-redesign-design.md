# Ping 웹사이트 전면 개편 — 디자인 스펙

- 작성일: 2026-05-17
- 작업 브랜치: `feat/web-redesign`
- 대상: `web/`(현재 `https://0minping.vercel.app` 배포 소스)

## 1. 목표

지금 배포된 `web/` 는 한 화면짜리 단조로운 다크 랜딩이고 한국어 헤드라인이 음절 단위로 깨진다. 이번 작업으로 Ping(macOS 메뉴바 2초 영상 메시지 앱)의 정체성을 한 호흡으로 전달하는 *cinematic product site* 로 바꾼다.

- 즉시 이해 가능한 3-Beat 데모(Option+P → 원형 거울 → 2초)
- macOS 13 Ventura+ 지원을 명확히 알리고, Apple Silicon-first 감성과 미니멀 다크 톤 유지
- shadcn-ui + Tailwind v4 + React Bits 컴포넌트 구성을 정착
- 한국어 타이포 보정(`word-break: keep-all`)
- 초대 경험(`/invite/:token`) 도 별도 풀페이지로 격상

## 2. 스택 정비

| 항목 | 현재 | 변경 후 |
|---|---|---|
| 스타일 | 손수 작성한 CSS, Tailwind 미설치 | **Tailwind v4** (`@tailwindcss/vite`) + `@theme` 토큰 |
| 컴포넌트 라이브러리 | `components.json` 만 존재 | **shadcn-ui** 최소 primitive 설치 (`button`, `card`, `badge`, `separator`) |
| 모션/그래픽 | `Orb`, `ShinyText` | 위 + `Aurora`, `SplitText`, `ScrollFloat`, `SpotlightCard`, `ClickSpark` (React Bits) |
| 라우팅 | App.tsx 안에서 정규식 분기 | `routes.tsx` 로 분리 (의존성 추가 없이 자체 분기 유지) |

> 참고: `components.json` 의 `@react-bits` registry 가 이미 등록돼 있으므로 React Bits 컴포넌트는 해당 registry 의 source(`https://reactbits.dev/r/{name}.json`)를 그대로 사용한다.

## 3. 디자인 토큰

```css
@theme {
  --color-bg:        #0A0B09;
  --color-bg-elev:   #11130F;
  --color-fg:        #F7F4EA;
  --color-muted:     rgba(247, 244, 234, 0.62);
  --color-subtle:    rgba(247, 244, 234, 0.42);
  --color-border:    rgba(247, 244, 234, 0.10);
  --color-accent:    #8DE8B9;   /* signal mint */
  --color-record:    #FF6254;   /* recording dot */
  --color-warm:      #F4FF78;   /* aurora 보조색 */

  --radius-sm: 12px;
  --radius-md: 18px;
  --radius-lg: 24px;
  --radius-pill: 999px;

  --shadow-cta:   0 18px 54px rgba(141, 232, 185, 0.24);
  --shadow-card:  0 24px 60px rgba(0, 0, 0, 0.4);
}
```

타이포

- 본문/디스플레이: 시스템 폰트(`-apple-system, "Apple SD Gothic Neo", "Pretendard Variable", ...`). 과거 합의대로 시스템 폰트 우선.
- 키캡: `ui-monospace, SFMono-Regular, Menlo, monospace`.
- 한국어: `word-break: keep-all; overflow-wrap: anywhere;` 전역 적용.

## 4. 페이지 구조 — `/`

순서대로 한 컬럼 흐름.

### 4.1 Sticky Nav
- 좌측: 브랜드(원형 P 마크 + Ping)
- 가운데: 앵커 텍스트 링크 — *작동 방식 · 기능 · 다운로드*
- 우측: 다운로드 pill CTA (shadcn `Button` variant `secondary`)
- 스크롤 50px 이상 시 backdrop-blur 강해짐

### 4.2 Hero (full-bleed)
- 배경: `Aurora` (React Bits) — 색상 `[#0A0B09, #8DE8B9, #F4FF78]`, blend 모드 부드럽게
- 상단 floating chip: mock macOS 메뉴바 풀팝 — `[P] Ping · Option+P`
- 헤드라인: `SplitText` 두 줄 (등장 시간차 0.08s/glyph)
  - `말로 다 하기 전에,`
  - `2초만 보내세요.` (mint gradient 강조)
- 리드 카피 1문장
- CTA 2개: 기본(다운로드) + 보조(작동 방식 보기 ↓)
- 우측 보조 visual: 작아진 `Orb` (크기 360px), 안에 mock recording 인디케이터

### 4.3 3-Beat Demo strip
- 섹션 타이틀: *Option+P → 2초 → 끝.*
- 가로 3컷 (모바일 세로 스택), 각 컷은 SVG/CSS 일러스트
  1. **불러오기** — 검은 데스크탑 + 상단 메뉴바에 Ping 아이콘 글로우
  2. **위치 정하기** — 화면 위 원형 거울이 나타나는 모션 (mint glow)
  3. **2초 보내기** — Enter 키, 빨간 record dot, 2→0 카운트다운 링
- `ScrollFloat` 로 컷 순차 진입

### 4.4 Features Grid (2×2)
- `SpotlightCard` 4장
  1. 원형 거울 카메라 — 기존 `Orb` 를 카드 내부 visual 로 이관
  2. Option+P 단축키 — 키캡 SVG
  3. 정확히 2초 — 카운트다운 링 visual
  4. 방 단위 공유 — 토큰/룸 아이콘
- 각 카드 1문장 설명 + 1줄 보조 텍스트

### 4.5 Privacy & Spec strip
- 한 줄 4-칸 라이트 보더 그리드
  - Apple Silicon Mac 권장
  - macOS 13 Ventura+
  - ~24MB
  - 메뉴바에서만 동작 · 영상은 만료 후 삭제

### 4.6 Final CTA Block
- 대형 다크 카드 (full-width, radius-lg)
- 좌: 헤드라인 *"2초면 충분합니다."* + 버전 chip `Ping v0.1.0`
- 우: 기본 CTA + "변경 사항" 텍스트 링크
- CTA 클릭 영역에 `ClickSpark` 가벼운 인터랙션

### 4.7 Footer
- 좌: 브랜드 + `© 2026 Ping`
- 우: GitHub · 라이선스 · 개인정보 (현재 없는 페이지는 placeholder 링크로 두되, GitHub 만 실제 링크)

## 5. `/invite/:token` 풀페이지

별도 화면 컨셉(랜딩 안 panel 아님).

- 배경: 더 어두운 톤의 `Aurora` (채도 -30%)
- 좌측 컬럼:
  - eyebrow: *초대장*
  - h1: **초대장이 도착했어요**
  - 리드: *Ping을 설치하고 아래 코드를 앱 안에 붙여 넣으면 같은 방에서 메시지를 주고받을 수 있어요.*
  - 토큰 칩(가로 길게, monospace, 클릭 시 클립보드 복사 + `ClickSpark`)
  - 3-step 인디케이터 — 설치 → 앱 열기 → 토큰 붙여넣기
  - CTA 2개: 다운로드 / 이미 설치했어요
- 우측 컬럼: 작은 mock 앱 윈도우 일러스트 (룸 화면) — SVG

## 6. 모션 원칙

- 1회성 등장 애니메이션은 0.6s 이하, easing `cubic-bezier(0.22, 1, 0.36, 1)`
- 스크롤 트리거는 `ScrollFloat` 한 종류로 통일
- `Aurora` 와 `Orb` 는 무한 루프, `prefers-reduced-motion: reduce` 시 정적 fallback
- 호버 모션은 transform 만 (layout shift 없음)

## 7. 디렉터리 변경 후 모양

```
web/src/
├── components/
│   ├── ui/                  # shadcn primitives
│   │   ├── button.tsx
│   │   ├── card.tsx
│   │   ├── badge.tsx
│   │   └── separator.tsx
│   ├── bits/                # React Bits 컴포넌트
│   │   ├── Orb.tsx (이관)
│   │   ├── ShinyText.tsx (이관)
│   │   ├── Aurora.tsx
│   │   ├── SplitText.tsx
│   │   ├── ScrollFloat.tsx
│   │   ├── SpotlightCard.tsx
│   │   └── ClickSpark.tsx
│   ├── sections/
│   │   ├── SiteNav.tsx
│   │   ├── Hero.tsx
│   │   ├── DemoStrip.tsx
│   │   ├── FeaturesGrid.tsx
│   │   ├── SpecStrip.tsx
│   │   ├── FinalCTA.tsx
│   │   └── SiteFooter.tsx
│   └── invite/
│       ├── InviteView.tsx
│       ├── TokenChip.tsx
│       └── InviteSteps.tsx
├── routes.tsx               # 경로 분기 (정규식 유지, 깔끔하게 분리)
├── App.tsx                  # routes 호출만
├── main.tsx
└── styles.css               # @import "tailwindcss"; + @theme tokens
```

## 8. Out of scope

- 다운로드 상세 페이지/모달
- FAQ 섹션
- i18n
- 실제 macOS UI 스크린샷 (SVG/CSS 일러스트로 대체)
- 라우터 라이브러리 도입 (React Router 등 — 현재 정규식 분기로 충분)
- 다크/라이트 토글 (다크 단일 톤 유지)

## 9. 성공 기준

1. `npm run build` 무경고 성공
2. Lighthouse Performance ≥ 85, Accessibility ≥ 95 (로컬 측정)
3. 한국어 헤드라인 음절 분리 깨짐 없음 (모든 viewport)
4. 메뉴바 mock chip / 3-Beat demo / Features grid / Final CTA 까지 1280×800·390×844 둘 다 깨지지 않음
5. `/invite/test-token` 으로 진입 시 별도 풀페이지 경험이 보임
6. `prefers-reduced-motion: reduce` 환경에서 큰 애니메이션이 정지함
