# Windows Email Account Implementation Plan

> Native 실행: 승인된 선택 A를 현재 세션에서 구현한다. 사용자 지침에 따라 자동 테스트·검증 빌드·별도 리뷰·검증 CI는 실행하지 않는다.

**Goal:** 기존 Ping UID를 이메일에 연결하고 여러 Windows PC에서 별도 세션으로 같은 계정을 사용한다.

**Architecture:** Supabase Auth REST를 기존 partial client에 추가한다. 설정의 이메일 인증 모델이 메일 요청·코드 확인을 처리하고 기존 앱 계정 전환이 인증된 계정을 원자적으로 저장한다. 서버 DB/RPC/Vercel 변경은 없다.

**Tech Stack:** C#/.NET 10, WinUI 3, Supabase Auth REST.

**Spec:** `docs/superpowers/specs/2026-10-05-windows-portable-account-gap.ko.md`

## Global Constraints

- Anonymous Auth 기본 진입 유지, Windows의 선택형 이메일 인증만 허용.
- 같은 UID 유지, 기존 계정·룸·메시지의 임의 병합·삭제 금지.
- 인증번호·세션·SMTP 비밀을 로그/채팅/Git에 기록하지 않는다.
- 현재 계정 연결과 다른 계정 로그인을 구분한다. 확인 실패 시 현재 계정 보존.
- 운영 Ping ref `qxjtprxvjmaxlbtljcjw` 고정, 전체 config push 금지.
- macOS 제품 불변식 유지. 자동 검증 없음.

## Task 1: Auth REST와 원자적 로그인 저장

- [x] `EmailAccountAuthentication.cs`: 연결 상태, 인증 결과(토큰 비공개), 입력/오류 표시.
- [x] `SupabaseClient.EmailAccounts.cs`: 상태 조회, 이메일 연결 요청, 기존 계정 OTP 요청, 코드 확인. UID/이메일/확인 상태 검증, 새 사용자 자동 생성 금지.
- [x] 같은 partial 파일에서 검증된 결과를 기존 `CommitAccountsLockedAsync`로 저장, 기존 계정 목록 보존.
- [x] Commit: `2f7d302` — `feat(windows): add email account authentication`

## Task 2: 설정 UI와 계정 수명 연결

- [x] `EmailAccountViewModel.cs`: 연결/로그인 요청·코드 확인·재요청·취소·저장 재시도 상태.
- [x] `SettingsWindowViewModel.cs`, `SettingsWindow.xaml`: 연결 상태, 이메일·인증번호 입력, 기존 계정 로그인, 글꼴·기존 카드 일관성.
- [x] `App.xaml.cs`, `AppCoordinator.cs`: 인증 결과를 기존 shutdown/계정 저장/rebootstrap에 연결, 저장 실패 재시도 보관, 끊어진 세션에서도 이메일 로그인 접근.
- [x] Commit: `6f2699f` — `feat(windows): connect email login to account settings`

## Task 3: 제한된 운영 설정과 사용자 안내

- [x] 정확한 Auth 필드만 PATCH하는 운영 스크립트와 SMTP/템플릿 안내. credential 없이 적용하지 않는다.
- [x] AGENTS/spec의 이메일 금지 조항을 승인된 Windows 예외로 갱신한다.
- [x] 구현/미적용 운영 설정/미생성 설치물/미검증 상태를 구분하여 기록한다.
- [x] Commit: `9c4d3b8` — `docs(windows): document email account activation`

## 산출물 생성

- [x] 0.4.16 EXE/MSIX를 `build_only=true`로 생성했다. [CI 37292289850](https://github.com/0mininseoul/ping/actions/runs/37292289850), source `7420561`, packaging success (5m40s). 테스트 restore/실행 단계 skipped. 테스트·smoke·앱 실행 없음.
- [x] `windows/dist/PingSetup-v0.4.16.exe`와 `windows/dist/email-0.4.16/`의 MSIX artifacts를 내려받았다. 설치·실행·메일 발송 확인 없음.
- [x] GitHub `codex/windows-parity`에 커밋을 올렸다. 운영 SMTP/Auth 설정은 미적용. 사용자 답변은 “모름 없을걸?”이며 관리 토큰/SMTP 정보가 없다.

## 후속 논의

사용자가 이메일 없이 `사용자이름#0000`만으로 로그인하는 안에 의견을 요청했다. 이는 아직 인증 방식 변경의 확정 지시가 아니다. 공개 식별자만으로 계정 소유권을 인정하지 않는다. 이름/태그+비밀번호 또는 기존 기기 승인 방식은 별도 설계·구현이 필요한 대안이며 현재 제공했다고 주장하지 않는다. 이메일 코드는 보존하고 운영 이메일 설정은 적용하지 않았다.
