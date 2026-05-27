# 크로스플랫폼 계정 복구 — 설계/결정 노트

**상태: DEFERRED (결정만 기록, 지금은 구현하지 않음)**

**작성일:** 2026-05-27

**한 줄 요약:** 일반 재설치는 이미 계정이 유지되므로 지금은 복구 기능을 만들지 않는다. 유저가 늘면 "설정 창의 선택적 이메일 복구"를 **단일 크로스플랫폼 복구 수단**으로 추가한다.

---

## 배경 — 현재 인증/세션 모델

Ping(macOS)과 PingWindows(.NET)는 **동일한 인증 모델**을 쓴다:

- 첫 실행 시 Supabase **Anonymous Auth** 로 `/auth/v1/signup` 호출 → 익명 `auth.users` 생성.
- 세션(access/refresh token + userId)은 **로컬 파일 하나**에만 저장:
  - macOS: 샌드박스 컨테이너 내 `Application Support/Ping/SupabaseSession.json` (+ 레거시 `UserDefaults`). `Ping/Backend/SupabaseClient.swift`.
  - Windows: `%LocalAppData%\Ping\SupabaseSession.json`. `windows/src/Ping.Windows.Core/Backend/SupabaseClient.cs`.
- 닉네임·룸 등은 서버(`public.profiles` 등)에 그 익명 userId로 묶여 있다. 즉 **로컬 세션 파일이 "나는 유저 X다"를 증명해야만** 서버가 X의 데이터를 돌려준다. 기기 하드웨어를 인식하는 장치는 전혀 없다.

## 확인된 사실 (조사 결과)

1. **일반 재설치는 이미 계정을 유지한다 — 양 플랫폼 모두.**
   - macOS: 앱을 휴지통에 버려도 샌드박스 컨테이너(`~/Library/Containers/<bundle-id>/`)는 OS가 자동 삭제하지 않는다 → 세션 파일 잔존.
   - Windows: Inno Setup 설치 제거기(`windows/installer/PingSetup.iss`)는 `Program Files`만 관리하고 `%LocalAppData%\Ping`은 건드리지 않는다 → 세션 파일 잔존.
2. **그래서 현재 미보장 케이스는 두 가지뿐이다:**
   - (a) **완전 삭제** — 클리너 툴/수동으로 appdata·컨테이너까지 제거.
   - (b) **새 기기로 이사** — 새 Mac/PC, 특히 **Mac ↔ Windows 이동**.
3. **Keychain 은 macOS에서 사용 금지.** ad-hoc 서명 앱을 자주 교체 배포할 때 Keychain ACL 승인 팝업이 재발하므로 `SupabaseSessionStore` load/save/clear 경로에 `SecItem*` 를 넣지 않는다. (`AGENTS.md`, `PING_PROJECT_SPECIFICATION.md` 명시)
4. **2026-05-27 정리 작업에서 발견된 orphan 14개의 원인은 일반 재설치가 아니라**, README에 문서화된 "온보딩 QA를 위해 `SupabaseSession.json`을 일부러 삭제"하는 관행 + 온보딩 미완료(프로필 미생성)였다. production 유출이 아님. 실유저(영민·나롱) 2개만 남기고 정리 완료.

## 결정

### 지금: 아무것도 구현하지 않는다
- 일반 재설치는 이미 동작하고, 유저가 소수(현재 2명)인 시점에 복구 시스템은 과투자(YAGNI).

### 트리거: 아래 중 하나라도 충족되면 착수
- 활성 유저 약 **100명** 돌파, **또는**
- "재설치/기기 변경 후 계정·룸을 잃었다"는 유저 문의가 **누적 2건 이상** 발생.
  (수치는 권장값 — 착수 시점에 재조정 가능.)

### 착수 시 만들 것: 설정 창의 선택적 이메일 복구 (단일 크로스플랫폼 수단)
- 가입 흐름은 그대로 익명 유지. **원하는 유저만** 설정 창에서 이메일을 "복구 수단"으로 등록(매직링크/OTP). Supabase에서 익명 유저에 이메일을 연결하면 영구 계정으로 전환된다.
- 새 기기/완전 삭제 후 그 이메일로 인증 → **같은 userId 복원** → 닉네임·룸 그대로. macOS·Windows 공통 동작.
- opt-in이라 **온보딩 마찰 0**. 유저는 이메일을 잘 잃어버리지 않아 복구 성공률이 높다.
- 참고: 현재 영민 계정(`c5ceae2f...`)이 `ping-recovery+<uuid>@ping-recovery.invalid` 영구 계정으로 **수동** 전환돼 있다. 이 패턴(익명→영구 전환)이 곧 구현의 원형이다.

## 기각한 대안

- **복구 코드(유저가 직접 보관):** "코드를 저장하세요" 자체가 UX 부담이고, 분실 시 영구 복구 불가. 이메일이 모든 면에서 우위라 채택하지 않음.
- **iCloud(NSUbiquitousKeyValueStore)를 주 복구 수단으로:** Apple 전용이라 **Mac→Windows 이동을 원천적으로 못 한다.** "한 계정이 모든 기기(Windows 포함)를 따라다닌다"는 목표를 단독으로 달성 불가. iCloud는 잘해야 "Apple 기기끼리 무탭 자동복원" 편의 레이어이며, 진짜 크로스플랫폼 정체성은 못 됨. (필요하면 이메일 복구 위에 Apple 한정 옵션으로 나중에 얹을 수 있음.)
- **macOS Keychain:** 위 사실 #3 — ACL 팝업 문제로 사용 금지.

## 비목표 (Non-goals)
- 지금 시점의 어떠한 코드 변경도 비목표.
- 강제 로그인/회원가입 도입 — 무로그인 철학 유지.
- iCloud / Windows Credential Manager(DPAPI) 자동복원 — 향후 선택적 편의 레이어로만 검토, 본 결정의 범위 아님.
