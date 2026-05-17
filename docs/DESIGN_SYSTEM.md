# Ping Design System

Ping은 macOS 메뉴바에 상주하는 2초 영상 메시지 앱이다. UI는 화려한 데모형 글래스가 아니라, 작업 중인 사용자가 빠르게 이해하고 지나갈 수 있는 조용한 네이티브 도구처럼 보여야 한다.

## Design Direction

**Quiet Native Glass**

- macOS 시스템 UI처럼 차분하고 가벼운 표면을 기본으로 쓴다.
- `.glassEffect()`는 핵심 오브젝트, 작은 컨트롤, floating mirror에 제한해서 사용한다.
- 큰 리스트 행 전체를 진한 유리 카드로 만들지 않는다. 리스트는 밝은 control surface + 얇은 stroke + 낮은 shadow를 쓴다.
- 파란색은 CTA, 진행률, focus edge에만 사용한다.
- 화면의 기억점은 “작업 중 바로 열리는 작은 거울”이다. 장식적 카드나 과한 glow가 주인공이 되면 안 된다.

## Product Tone

- 빠름: 한 번의 단축키, 한 번의 Enter.
- 가까움: 영상 메시지보다 “잠깐 보는 느낌”을 강조한다.
- 방해 없음: 설정과 전송 후 불필요한 설명을 줄인다.
- 네이티브: macOS 기본 컨트롤과 같은 밀도, 여백, 텍스트 위계를 따른다.

## Typography

시스템 폰트만 사용한다. Ping은 macOS 전용 앱이므로 SF Pro / Apple SD Gothic Neo fallback이 가장 자연스럽다.

| Token | Size / Weight | Usage |
|---|---:|---|
| `display` | 28 / bold | 온보딩 주요 제목 |
| `title` | 20 / semibold | 섹션 제목, 큰 입력값 |
| `body` | 14 / medium | 설명문, 행 본문 |
| `label` | 13 / medium | 버튼, 상태값 |
| `caption` | 12 / regular | 보조 설명, 카운터 |
| `numeric` | 24 / semibold tabular | 거울 카운트다운 |

Rules:
- 헤드라인은 한 줄을 우선하되, 한글 기준 13자 이상이면 2줄 허용.
- 본문은 회색 계열로 낮추고 줄간격을 3pt 정도 둔다.
- 버튼 텍스트는 크기를 키우기보다 control height와 여백으로 중요도를 만든다.
- 배경이 밝거나 대비가 낮은 표면에서는 같은 크기의 토큰도 한 단계 무겁게 쓸 수 있다. 예: glass 위 `caption`은 regular 대신 medium, 흐린 배경 위 `label`은 semibold까지 허용한다.

## Color

| Token | Role |
|---|---|
| `windowBackground` | 기본 앱 창 배경 |
| `controlBackground` | 카드보다 낮은 행/입력 표면 |
| `accent` | 진행률, primary CTA, focus edge |
| `success` | 권한 허용, 완료 |
| `warning` | 오류, 재시도 |
| `destructive` | 녹화, 위험 상태 |
| `glassTint` | colored shadow와 subtle glass edge |

Color sources are specified in OKLCH first, then approximated in SwiftUI sRGB tokens because SwiftUI does not expose a native OKLCH `Color` initializer.

| Token | OKLCH Source | Swift Token |
|---|---:|---|
| `accent` | light `oklch(58% 0.17 248)`, dark `oklch(72% 0.12 245)` | `PingDesign.ColorToken.accent` |
| `success` | light `oklch(66% 0.16 146)`, dark `oklch(73% 0.13 150)` | `PingDesign.ColorToken.success` |
| `warning` | light `oklch(67% 0.17 70)`, dark `oklch(78% 0.13 78)` | `PingDesign.ColorToken.warning` |
| `destructive` | light `oklch(63% 0.22 29)`, dark `oklch(70% 0.18 29)` | `PingDesign.ColorToken.destructive` |
| `glassTint` | light `oklch(72% 0.11 220)`, dark `oklch(68% 0.09 218)` | `PingDesign.ColorToken.glassTint` |

### Light And Dark Mode

Dark mode must not be a simple inversion of the light design. It should remain native and quiet:

- Surface fills use explicit light/dark tokens in `PingDesign.Surface`; do not build dark surfaces from `Color.white.opacity(...)`.
- Onboarding dark mode uses a deep charcoal base with restrained cool wash. Do not place a large white or gray radial wash over the window; it turns the UI into a flat gray sheet.
- Input cards in dark mode use `inputCardFill` and `inputFieldFill`, never the light-mode white glass surface. The field should read as a crisp dark control with a blue focus edge.
- Dark input cards must stay darker than surrounding highlight washes. If a text field looks like a light gray plate in dark mode, lower the dark `inputCardFill` and `inputFieldFill` lightness before adding more border.
- Dark rows and panels should be slightly lifted charcoal with a cool tint, not translucent white sheets.
- Hairlines use white in light mode and a muted blue-gray in dark mode so borders stay visible without becoming chalky.
- Warning colors are warmer and lighter in dark mode. Avoid reusing the darker light-mode amber on dark backgrounds.
- Accent shadows use layered colored shadows with lower dark-mode opacity. Avoid stacking blue glows; mix `accent` and `glassTint` sparingly and keep the glow behind the control.

Rules:
- dominant palette는 시스템 배경 + 흰색 material + 낮은 blue tint다.
- cyan/blue glow는 10-18% opacity 범위를 넘기지 않는다.
- 회색 glass를 여러 겹 쌓지 않는다. 한 표면에는 fill, stroke, shadow를 각각 한 번만 강하게 쓴다.
- dark mode에서는 blue/cyan 계열이 전체 화면을 지배하지 않게 한다. Accent는 CTA, focus, floating mirror depth에만 제한한다.

## Shape And Elevation

| Token | Value | Usage |
|---|---:|---|
| Window radius | 28 | Onboarding window |
| Panel radius | 18 | 입력 패널, permission list |
| Row radius | 16 | Permission row |
| Control radius | capsule | Buttons, chips |

Elevation:
- 검은 shadow를 기본값으로 쓰지 않는다. elevation은 shadow factory인 `PingDesign.Shadow.colored(...)`의 layered colored shadow를 기본으로 삼고, native control shadow가 필요한 경우만 예외로 둔다.
- Floating mirror만 강한 colored shadow를 허용한다.
- 온보딩 행 shadow는 colored shadow 기준 opacity 0.04-0.08, y 5-10 범위로 제한한다.
- inner highlight는 white stroke 0.12-0.35 opacity를 사용한다.
- dark mode shadow는 black opacity로 깊이를 만들지 않는다. `PingDesign.Shadow.colored(..., darkColor:darkAmbientOpacity:)`로 색상과 불투명도를 명시하고, contact layer는 light mode보다 낮게 둔다.

## Motion

- Onboarding progress gauge animates with a 0.34s ease-in-out fill.
- Buttons use a shared 0.16s ease-out hover lift in `GlassButton`.
- Wizard content may change immediately; the progress gauge carries the transition cue.
- Respect macOS Reduce Motion by disabling decorative progress animation.

## Components

### Brand Lockup

Onboarding header uses a compact lockup:

- 38pt `HeaderLogo` asset on the left
- 6pt gap
- `Ping` wordmark in the dedicated `wordmark` font token

The icon should use `Resources/AppIcon.png` through `HeaderLogo.imageset` without clipping. Do not use the monochrome menu bar symbol in the onboarding header.

### Button

Variants:
- `primary`: accent fill, white highlight stroke, 낮은 accent shadow.
- `secondary`: light material fill, subtle stroke, shadow 거의 없음.
- `disabled`: opacity 0.45, shadow 제거.

Primary button은 한 화면에 하나만 둔다. Accent shadow는 버튼보다 먼저 보이지 않게 낮게 둔다. Wizard footer actions are right-aligned. Do not show disabled ghost buttons in onboarding footers.

Hover:
- Apply hover motion only inside `GlassButton`, not per screen.
- Use a subtle 1.018 scale and -1pt lift with a 0.16s ease-out animation.
- Disable decorative hover motion when macOS Reduce Motion is enabled.

### Permission Row

행 전체를 진한 glass card로 만들지 않는다.

Structure:
- 40-44pt icon tile
- title + detail
- trailing status/action

Granted state:
- green check icon + `허용됨`

Pending state:
- compact `허용` secondary button

Denied/restricted state:
- row action changes to `설정`
- show one subdued settings notice: `시스템 설정에서 켜야 합니다`
- footer primary action changes to `시스템 설정 열기`
- remove redundant recheck actions once every permission is granted

### Onboarding Input Field

입력 화면은 큰 glass card 안에 바로 `TextField`를 두지 않는다. 라벨, 입력 surface, helper text를 분리해서 포커스 커서와 placeholder가 시각적으로 충돌하지 않게 한다.

Structure:
- fixed label row
- plain input card surface, not `GlassPanel`
- 52pt inset rounded input surface
- helper text row outside the active input surface

Rules:
- focused surface uses a subtle accent stroke, not a large glow
- focused surface does not cast its own shadow
- text inputs must not nest glass surfaces; nested `glassEffect` creates visible rounded artifacts while typing
- nickname may use short placeholder copy
- room name is required and has no placeholder
- after nickname, onboarding must offer `룸 생성하기` and `룸 참여하기` as equal primary choices; `나중에 하기` stays visually small and secondary

### Onboarding Screen

Structure:
- 상단 header: 앱 이름, step count, progress track
- 중앙 content: 한 개의 headline block + 필요한 controls
- 하단 footer: 한 줄 action bar

Rules:
- 첫 화면을 제외한 모든 단계에는 좌측 `이전` 버튼을 둔다.
- footer 버튼을 세로로 쌓지 않는다.
- footer의 primary action은 우측 끝에 둔다.
- 화면 중간에 큰 glass 카드 3개를 쌓지 않는다.
- 배경 gradient는 hard cutoff 없이 전체 창에 부드럽게 깔린다.

## Copy

Primary onboarding copy:

> 보고 싶을 때 바로 Ping

Subtitle:

> Option+P로 거울을 열고, Enter로 2초를 보냅니다.

Copy rules:
- “2초 영상 메시지”보다 “보고 싶을 때 바로”를 우선한다.
- 기능 설명은 subtitle이나 chip으로 보낸다.
- 시스템 권한 설명은 짧고 구체적으로 쓴다.

## Anti-Patterns

- 회색 glass 카드가 화면을 지배하는 UI
- primary/secondary 버튼이 모두 같은 무게로 보이는 UI
- glow가 CTA보다 먼저 보이는 UI
- 설명문이 기능 튜토리얼처럼 길어지는 UI
- 랜딩 페이지 같은 과한 히어로 구성
