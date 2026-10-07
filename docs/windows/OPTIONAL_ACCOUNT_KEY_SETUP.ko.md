# 선택형 닉네임·비밀키 연결 — 운영 적용 기록

2026-10-07: 소스 구현을 추가했다. 운영 DB/API 적용, 새 EXE 생성, 실행 확인은 하지 않았다. 현재 설치된 v0.4.18 EXE에는 이번 기능이 포함되지 않는다.

이후 사용자의 명시적 요청으로 화면 캡처용 빌드와 예시 데이터의 native UI 렌더링을 수행했다. 새 UI 스크린샷은 `ACCOUNT_KEY_UI.ko.md`에 저장했다. 실제 인증·서버 연결 검증이나 운영 적용은 수행하지 않았다.

## 사용자 흐름

가입 없이 닉네임을 정하는 온보딩은 유지한다. 닉네임 입력 아래 작은 회색 `혹시 기존 계정이 있나요?`를 누르면 현재 닉네임·비밀키로 연결한다. 키는 처음에 만들지 않는다. 필요한 사람이 기존 PC의 **설정 → 일반 → 다른 PC에서 이어 쓰기 → 비밀키 만들기**에서 직접 정한다. 설정에도 기존 계정 연결 진입점이 있다.

계정의 원래 Supabase UID, 방, 대화와 Storage 소유권을 유지한다. 각 PC는 서로 다른 Auth 세션을 사용하며 refresh token을 복사하지 않는다. 기존 연결 기기는 키를 바꿔도 유지된다. 닉네임을 바꾸면 새 닉네임으로 연결한다. 중복 닉네임은 허용하며 동일 닉네임·키 조합만 거부한다.

키는 공백과 대소문자를 구분하는 12~128자다. 원문은 디스크/DB/로그에 저장하지 않는다. 현재 세션이 있는 기기에서 키를 다시 정할 수 있다. 모든 기기와 키를 잃으면 복구할 수 없다. 현재 방식은 PC에 로그인 상태를 저장하며 메모리 전용 공용 PC 로그인과 원격 기기 철회는 별도 작업이다. `이 PC에서 제거`는 서버 계정 삭제나 방 탈퇴, 서버 세션 철회가 아니다.

## 기존 서버 안에서 필요한 적용

대상은 Supabase `qxjtprxvjmaxlbtljcjw` / org `nvyhcwxyemylsqjlbdpo` / name `Ping`과 기존 `https://0minping.vercel.app` 프로젝트다. 다른 프로젝트로 옮기거나 새 서버/SMTP/Edge Function을 만들지 않는다.

1. Ping 계정으로 접근할 수 있는 연결이 필요하다. 현재 Supabase MCP는 이 프로젝트에 대한 권한을 거부했다. Vercel 연결에서 조회된 프로젝트는 `archy_v2`, `archy-dev`뿐이며 Ping은 보이지 않았다. 로컬 `.vercel/project.json`도 없다. 다른 팀의 프로젝트에 변경을 적용하지 않았다.
2. 기존 pinned wrapper로 CLI 접근 권한과 대상 프로젝트를 확인한 후 `./scripts/supabase-ping.sh db push`로 `supabase/migrations/20261007000100_optional_account_key.sql`을 적용한다. 이 세션의 wrapper `migration --help` 실행은 종료 코드 1로 실패했다. 따라서 migration은 오프라인 소스로 작성했으며 원격 적용 이력은 없다. `supabase config push`로 운영 설정 전체를 덮어쓰지 않는다.
3. 기존 Vercel Production의 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`를 그대로 사용한다. URL은 pinned 프로젝트와 같아야 한다. service role은 서버에만 둔다.
4. 서버 전용 `PING_ACCOUNT_KEY_PEPPER`를 추가한다. 안전한 무작위 32바이트 이상을 base64로 인코딩한 값(최소 43자)을 사용한다. 이 값은 사용자의 비밀키가 아니라 서버가 지문·내부 인증 비밀번호를 도출하는 비밀이다. 환경 변수는 민감 정보로 저장하고 별도 안전한 백업을 유지한다. 값이 없어지거나 바뀌면 기존 연결용 키 인증이 깨지므로 재배포마다 재생성하지 않는다. 클라이언트, Git, 채팅, 빌드 출력에 넣지 않는다.
5. migration과 `api/account-key.ts`가 기존 Production에 배포된 뒤 `PING_ACCOUNT_KEY_ENABLED=1`로 활성화하여 재배포한다. 기본값은 비활성이고, 설정/DB가 부족하면 API는 503으로 실패한다. Supabase의 기존 password grant를 사용하며 메일 발송·SMTP나 사용자 이메일 입력은 필요 없다.
6. 이 커밋을 포함한 Windows 패키지를 별도 생성·설치해야 UI가 반영된다. 기존 v0.4.18 설치 파일을 이번 산출물로 안내하지 않는다. 패키징을 요청받으면 `build_only=true`로 산출물만 생성한다.

## 구현 경계와 보안

`<uid>@accounts.ping.invalid`는 Supabase 표준 password sign-in을 쓰기 위한 서버 내부 식별자다. 실제 메일 주소를 받거나 메일을 발송하지 않는다. 익명 사용자의 동일 UID에 admin API로 identity를 연결하며 이미 실제 이메일 identity가 있으면 덮어쓰지 않는다.

키의 private scrypt 지문이 맞는 경우 서버가 UID별 고정 HMAC 인증 비밀번호로 Supabase에 로그인한다. 응답은 해당 기기의 새 access/refresh token만 포함한다. 키 변경은 Auth 비밀번호를 변경하지 않는다. 최초 identity 연결 후 registry 저장이 실패하면 현재 UID와 기존 세션은 보존되며 다시 설정할 수 있다.

private registry 및 속도 제한 테이블은 RLS를 켜고 직접 접근을 막는다. 공개 스키마의 RPC도 PUBLIC/anon/authenticated 실행 권한을 회수하고 service_role만 허용한다. 프로필 trigger는 로그인 닉네임만 동기화한다. 기존 메시지·룸·Storage 정책을 교체하지 않는다.

POST 요청 크기 제한, 캐시 금지, Vercel이 제공한 IP의 영속 제한(분당 12회), 로그인 이름의 시간당 40회 제한, 소유자 작업 분당 6회 제한을 적용한다. 잘못된 닉네임/키는 같은 문구로 응답한다. 서버 로그에 요청 본문·인증 오류·비밀 값·세션을 출력하지 않는다.

Windows는 인증 응답의 프로젝트/UID를 확인한다. 틀린 입력은 현재 coordinator를 닫지 않는다. 올바른 인증 이후 기존 coordinator를 종료하고 원자적 세션 저장을 수행한다. 실패하면 받은 세션을 메모리에 보존하고 설정에서 `연결 저장 재시도`를 제공한다. 재시작하면 메모리의 대기 세션은 사라지므로 다시 연결해야 한다.

## 실행 기록

- 백엔드 소스: `6408fb9`; Windows 연결 소스: `db675af`.
- 운영 DB/API는 적용하지 않았다. 기존 계정이나 방을 삭제/병합하지 않았다.
- 자동 테스트·검증용 빌드·린트·타입 검사·스모크 실행·화면 확인·별도 코드 리뷰·검증 CI를 수행하지 않았다. 구현 완료를 검증 통과로 표현하지 않는다.
