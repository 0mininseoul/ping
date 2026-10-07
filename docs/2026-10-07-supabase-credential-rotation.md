# Ping Supabase 자격 증명 교체 기록

2026-10-07, 프로젝트 `qxjtprxvjmaxlbtljcjw`, organization `0MIN` (`nvyhcwxyemylsqjlbdpo`). 비밀 값은 이 문서에 기록하지 않습니다.

## 완료한 접근 차단

- 기존 계정 PAT 19개 폐기, ChatGPT 로그인 연결 해제, Supabase 계정 전체 세션 로그아웃 처리.
- 이 Mac의 login Keychain에만 새 프로젝트 범위 관리 토큰 저장. 이름 `ping-this-mac-2026-10-07`, 만료 2026-10-14. 갱신도 이 Mac에서 수행해야 합니다.
- 기존 legacy `anon`/`service_role` API 키 사용 중지, 기존 기본 publishable/secret 키 삭제.
- 기존 HS256 JWT 서명 키 `52e1e56a-bcc1-4d23-b6a9-4cd865e16130` 폐기. 현재 ECC 사용자 서명 키는 유지.
- 기존 네 API 키는 Data API에서 모두 HTTP 401. 기존 anon/service_role을 새 공개 키와 함께 Authorization JWT로 보내도 HTTP 401. 기존 service_role JWT의 Storage 요청도 signature verification failed로 거부됨.
- Postgres 비밀번호 재설정. 새 비밀번호는 `Ping Supabase database (local)` Keychain 항목에만 저장. 새 비밀번호로 실제 Postgres `select 1` 성공. 후속 확인 시 현재 연결 외 다른 postgres client connection 0개.
- 관리 토큰과 비밀번호 모두 wrapper에서 로컬 Keychain을 사용. 외부 환경변수 덮어쓰기는 거부.
- 검증용 비밀 파일과 임시 Keychain 항목 삭제.

## GitHub와 운영 서버

- 저장소의 `PING_SUPABASE_ANON_KEY`와 `PING_SUPABASE_URL` Secret 삭제. Production/Preview 환경 Secrets 및 Variables에 Supabase 항목 없음.
- Windows CI의 Supabase GitHub Secret 의존성 제거. 공개 앱 설정은 `https://0minping.vercel.app/api/client-config`에서 가져옴.
- 워크플로/스크립트에서 Supabase Secrets/Variables 사용, 재등록 명령, Vercel Git 자동 배포 연결 재생성 명령을 발견하면 CI 검사 실패.
- GitHub push로 Vercel 운영/프리뷰 서버를 배포하는 연결 해제. 프로젝트 API에서 Git link 없음 확인. 앞으로 이 Mac에서 검토 후 CLI로 직접 배포.
- 새 서버 비밀 키는 Vercel sensitive 환경변수에만 보관. 공개 설정 API는 고정 Ping URL과 publishable 키만 반환하며, 비밀 키는 반환하지 않음.

## 앱 복구와 검증

- macOS 0.3.81 / build 93: Developer ID 서명, Apple 공증 및 staple 완료. DMG와 Sparkle appcast 배포. 이 Mac의 설치본도 새 publishable 키 사용 확인. 설치본의 기존 세션으로 Auth user 조회하여 기존 사용자 ID 유지 및 실접속 확인.
- Windows 0.3.47: GitHub Actions 서명/테스트/설치파일 게시 성공. 배포 사이트 latest-version 및 설치파일 업데이트.
- iPhone/Watch 0.1.2 / build 33: archive/export 및 App Store Connect 업로드 성공, Apple 빌드 처리 VALID. App Store 심사 제출 완료: `WAITING_FOR_REVIEW`, `AFTER_APPROVAL` 자동 출시, 전체 사용자에게 즉시 업데이트 출시. 버전 ID `cdeac2d4-f28d-41de-adc0-c6e3f996f8b5`. Apple 승인 전까지 App Store 구버전은 새 연결 설정을 사용할 수 없음.
- 새 클라이언트는 기존 공개 키가 거부되면 고정 배포 서버에서 새 publishable 키를 받아 한 번 재시도. 잘못된 프로젝트 또는 secret 키는 거부. 사용자 JWT가 거부되면 기존 refresh token으로 갱신하며 새 익명 계정을 임의 생성하지 않음.
- API 60개, PingKit 27개(복구 테스트 4가지 시나리오 포함), Windows Core 54개, Windows App 224개 테스트 통과. macOS 컴파일 및 실제 릴리즈 빌드 성공.

## 적용 범위

이 조치는 이전에 복사된 관리자 자격 증명과 GitHub에서 운영 서버로 이어지는 자동 경로를 차단합니다. 앱의 공개 publishable 키와 URL은 공개 정보이며 일반 사용자 접근은 RLS로 제한합니다. 공유 계정 소유자가 새 관리 인증을 직접 만들거나 비밀 값을 다른 기기에 복사하는 행위까지 하드웨어 단위로 금지하는 기능은 아닙니다. GitHub 관리자 수동 Secret 등록도 저장소 검사만으로 서버 측에서 금지할 수 없습니다.

이미 배포된 구버전에는 새 키 복구 코드가 없으므로 업데이트가 필요합니다. 새 버전은 기존 계정/연결을 보존하도록 구현했으나 이미 다른 이유로 폐기된 refresh token까지 되살릴 수는 없습니다. Apple 승인 시간 및 사용자의 앱 자동 업데이트 설정은 외부 조건입니다.
