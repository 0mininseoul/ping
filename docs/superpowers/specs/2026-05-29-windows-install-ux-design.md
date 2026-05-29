# Windows 설치·온보딩 UX 개선 설계 (2026-05-29)

## 배경

Windows 사용자는 랜딩페이지(`ping0min.vercel.app`)에서 `PingSetup-v*.exe`를 내려받아
설치한 뒤 Ping을 사용한다. 전체 깔때기(다운로드 → 설치 → 첫 실행 → 사용)를 검토한 결과
여러 UX 문제와 버그가 발견되어 4개 계층을 한 번에 개선한다.

## 발견된 문제 (요약)

| 구분 | 심각도 | 문제 |
|---|---|---|
| 첫 실행 | 🔴🔴 | 배포 MSIX에 Supabase 설정이 동봉되지 않음. 앱은 `%LOCALAPPDATA%\Ping\Supabase.json`을 읽고 없으면 예외. 일반 사용자는 URL/anonKey가 없어 **서비스 자체를 시작할 수 없음**. (macOS는 `Resources/Supabase.plist`를 번들) |
| 첫 실행 | 🔴 | 온보딩 Supabase 행이 막혔을 때 유일한 동작이 "Open config folder" → 막다른 길 |
| 인스톨러 | 🔴 | 62MB MSIX를 설치 도중 무진행률 다운로드. "Installing..."만 뜨고 별도 콘솔창 → 멈춘 듯 보임 |
| 인스톨러 | 🔴 | 설치 실패해도 Inno가 "완료"로 표시(`[Run]` 종료코드 미검사). 에러창+완료 동시 노출 |
| 인스톨러 | 🟠 | `Restart-Elevated`가 `-CreateDesktopShortcut/-AddToStartup/-IconPath` 인자 누락 |
| 랜딩 | 🟠 | OS 자동 감지 없음. Mac/Windows 버튼 동등 노출 → Windows 사용자가 DMG 받을 위험 |
| 랜딩 | 🟡 | SmartScreen 안내가 길고 `irm\|iex` 원라이너를 일반 사용자에게 노출 |
| 횡단 | 🟡 | 버전 문자열이 routes.tsx/appxmanifest/README/latest-version.txt에 분산 |

## 결정 사항

- **설정 동봉**: CI 시크릿(`PING_SUPABASE_URL`, `PING_SUPABASE_ANON_KEY`)으로 빌드 시
  `Supabase.json`을 MSIX에 주입. git 히스토리에 키를 남기지 않음. (시크릿은 등록 완료)
- **UX 우선**: 구현 복잡도가 올라가더라도 사용자 경험이 더 좋은 방향 선택.

## 설계

### 1. 백엔드 설정 동봉 (설치 직후 동작)

- **설정 탐색 우선순위 변경** (`SupabaseClient`, `PermissionProbe`):
  1. `%LOCALAPPDATA%\Ping\Supabase.json` (존재 시 우선 — 파워유저 오버라이드)
  2. 앱 설치 폴더 동봉본 `AppContext.BaseDirectory\Supabase.json` (기본값)
  - 공통 해석기 `SupabaseConfigLocator`로 분리하여 양쪽이 동일 규칙 사용.
- **패키징**: `Supabase.json`을 `Content(PreserveNewest)`로 MSIX 페이로드에 포함.
  실제 키 파일은 `.gitignore` 처리. 형식 안내용 `Supabase.example.json` 커밋.
- **CI**: 빌드 전 시크릿으로 `windows/src/Ping.Windows.App/Supabase.json` 생성.
  릴리스(서명) 빌드에서 시크릿 누락 시 빌드 실패 → 설정 없는 MSIX 재배포 방지.

### 2. 인스톨러 UX·버그

- `PingSetup.iss`: Inno 네이티브 `DownloadPage`로 cert/MSIX를 진행률·취소·재시도와 함께
  다운로드. 설치 단계는 로컬 파일만 사용.
- `install-ping-windows.ps1`: 다운로드 책임 제거(이미 받은 파일 사용), 콘솔 숨김 실행,
  실패 시 비정상 종료코드 반환. Inno가 종료코드를 검사해 실패를 정확히 처리하고
  한글 오류를 표시.
- `Restart-Elevated` 인자 누락 수정(직접 실행 경로용).
- `welcome.txt`(InfoBeforeFile) 간소화.

### 3. 랜딩 다운로드 UX

- `useOS()` 훅으로 Windows/Mac/기타 감지 → 해당 OS 버튼을 primary, 반대 OS는 secondary.
- SmartScreen 안내를 간결한 컴포넌트로, `irm|iex`는 `<details>` 고급 영역으로 이동.
- 버전/URL 상수는 `routes.tsx` 단일 출처 유지(정리).

### 4. 인앱 온보딩

- 동봉 설정으로 Supabase 행이 기본 Ready → 막다른 길 해소.
- `BootstrapAndLoadRoomsAsync` 실패 메시지 한글화 + "재시도" 동작.

## 검증

- C# 설정 해석 로직: `dotnet test`(macOS .NET 10)로 단위테스트 — 우선순위/누락/무효 케이스.
- 웹: `npm run build` + 브라우저 QA(OS 감지 분기).
- C#/MSIX/Inno 전체 빌드·서명·재배포: Windows/CI(`windows-client.yml`)에서 수행(필수 후속).

## 제약

- 현재 작업 환경(macOS)에서는 WinUI/MSIX/Inno를 컴파일·서명할 수 없음. 코드/스크립트/CI
  변경 후 실제 배포 반영은 Windows 빌드 1회가 필요하며 PR에 절차를 기재한다.
