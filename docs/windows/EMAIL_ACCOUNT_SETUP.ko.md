# Windows 이메일 계정 연결과 다른 PC 로그인

2026-10-05 승인한 선택형 이메일 인증 구현 안내. 현재 설치된 0.4.15에는 이 기능이 없다. 0.4.16 설치물을 `windows/dist/PingSetup-v0.4.16.exe`로 생성·다운로드했으며 설치/실행하지 않았다. 기존 Supabase와 Vercel을 유지한다. DB/RPC/Storage 변경은 없다.

## 사용자 흐름

1. ‘조세연’ 계정이 남아 있는 PC에서 **설정 → 일반 → 계정**을 연다.
2. 본인 이메일을 입력하고 **현재 계정에 이메일 연결**을 누른다.
3. 이메일에 표시된 인증번호를 입력하고 **이메일 연결 완료**를 누른다. 새 계정을 만드는 과정이 아니라 현재 UID에 이메일을 연결한다.
4. 다른 Windows PC에서 같은 화면에 이메일을 입력하고 **기존 계정 로그인**을 누른다.
5. 새 메일의 인증번호를 입력하고 **로그인 완료**를 누른다. 각 PC는 독립 세션으로 같은 UID의 서버 프로필·룸·메시지를 불러온다.

인증번호를 다시 요청하려면 약 60초 기다린다. 실제 발송 제한/만료는 Supabase 설정을 따른다. 인증번호는 메일 링크를 누르는 대신 Ping 입력란에 넣는다. 이미 다른 계정에 연결된 이메일을 현재 계정에 연결할 수 없으며 자동 병합하지 않는다. 기존 계정 로그인은 이 PC의 이전 계정을 저장 목록에 남긴다.

닉네임은 로그인 ID가 아니다. 같은 닉네임으로 새 계정을 만들면 UID가 다르다. 아직 이메일을 연결하지 않은 옛 계정을 닉네임만으로 복원할 수 없다. 로컬 영상 보관함과 기기별 설정은 다른 PC에 자동 복사하지 않는다.

## 운영자가 한 번 준비할 것

기존 [Ping Supabase](https://supabase.com/dashboard/project/qxjtprxvjmaxlbtljcjw/auth/providers)에서 이메일 provider와 manual linking을 켠다. 이메일 확인은 켜 두고 단일 기기 세션 제한은 끈다. Anonymous Auth는 유지한다.

Email Templates의 **Change Email Address**와 **Magic Link** 본문에 `{{ .Token }}`을 포함한다. 기존 본문과 링크를 유지하면서 숫자 인증번호를 추가할 수 있다. 인증번호 길이는 앱이 6~10자리 숫자를 허용한다.

일반 사용자에게 메일을 보내려면 기존 프로젝트의 Custom SMTP 설정에 메일 서비스의 host/port/user/password와 발신 주소를 연결해야 한다. Supabase 기본 발송은 프로젝트 팀 주소에 한정되므로 일반 이메일 로그인 배포 완료로 간주하지 않는다. 메일 서비스가 아직 없다면 SMTP 서비스 계정과 발신 주소 준비가 남는다. 자격증명은 대시보드나 로컬 비밀 저장소에 입력하며 채팅에 보내지 않는다.

관리 API를 쓸 경우 `scripts/configure-ping-email-auth.ps1`은 고정 ref/org/name을 확인하고 필요한 6개 Auth 필드만 PATCH한다. 전체 `supabase config push`를 실행하지 않는다. SMTP 자격증명을 수정하거나 출력하지 않는다. `PING_SUPABASE_MANAGEMENT_TOKEN`은 실행하는 로컬 프로세스에만 설정하고 저장하지 않는다.

```powershell
# 로컬 프로세스에 관리 토큰을 안전하게 준비한 뒤 변경 항목만 표시
.\scripts\configure-ping-email-auth.ps1
# 기존 Custom SMTP 설정이 준비된 뒤 제한된 설정 적용
.\scripts\configure-ping-email-auth.ps1 -Apply
```

현재 환경에 관리 토큰이 없어서 운영 설정을 적용하지 않았다. 사용자 메일이나 현재 계정에 임의 인증 요청을 보내지 않았다. 해당 스크립트를 작성했으나 실행 검증하지 않았다.

## 구현 상태와 한계

클라이언트 이메일 연결/인증번호 로그인/현재 계정 보존/저장 실패 재시도 UI를 구현했다. 운영 이메일 설정 활성화와 SMTP 준비가 끝나기 전에는 실제 로그인을 제공할 수 없다. macOS/iPhone의 이메일 로그인 UI는 이번 Windows 변경에 포함하지 않는다.

자동 테스트·검증 빌드·앱 실행·메일 발송 QA를 실행하지 않았다. 인증 결과의 저장 재시도는 실행 중인 앱 메모리에만 보관하며, 앱을 종료하면 인증번호를 새로 요청한다.

근거: [Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous), [Email OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless), [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [Auth configuration API](https://supabase.com/docs/reference/api/v1-update-auth-service-config).
