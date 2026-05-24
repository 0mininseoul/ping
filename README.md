# Ping

3초 영상 메시지 macOS 13 Ventura 이상 메뉴바 앱. Option+P 또는 Option+L 한 번으로 친구에게 보낸다.

## Supabase 설정

이 앱은 Supabase Anonymous Auth, Postgres RPC, 비공개 Storage 버킷 `ping-videos`를 사용한다. Supabase 프로젝트의 Project URL과 anon public key를 `Resources/Supabase.plist`에 넣는다. 이 파일은 git에 커밋되지 않는다.

```bash
cp Resources/Supabase.example.plist Resources/Supabase.plist
```

`Resources/Supabase.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_SUPABASE_ANON_KEY</string>
<key>PING_INVITE_BASE_URL</key>
<string>https://ping0min.vercel.app</string>
```

스키마는 `supabase/migrations/20260517000100_create_ping_backend.sql`에 있다. 원격 프로젝트에 연결한 뒤 적용한다.

```bash
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Supabase Dashboard의 Authentication 설정에서 Anonymous sign-ins가 켜져 있어야 한다.

## 설치

1. `Ping-v0.3.25.dmg`를 더블클릭해 마운트한다.
2. `Ping.app`을 Applications 폴더로 드래그한다.
3. 첫 실행은 우클릭 후 "열기"를 선택한다.
4. 카메라, 마이크, 알림 권한을 허용한다.
5. 닉네임을 입력한 뒤 룸을 만들거나 상대를 검색해 초대한다.

## 기존 룸과 익명 계정 보존

Ping은 이메일 로그인 없이 Supabase Anonymous Auth 세션을 로컬에 저장한다. 일반 업데이트나 `Ping.app` 교체는 기존 룸을 유지하지만, 앱 컨테이너의 `Application Support/Ping/SupabaseSession.json`을 삭제하면 새 익명 계정으로 시작한다. 온보딩 QA를 위해 세션을 지울 때는 반드시 이 파일을 먼저 백업하고, QA 뒤 원래 파일을 복구한 다음 Ping을 다시 실행한다.

## 사용

- Option+P: 얼굴만 거울을 띄운다.
- Option+L: 화면+얼굴 거울을 띄운다.
- Option+O: 내 룸/히스토리 창을 연다.
- Enter: 녹화 시작. 리뷰 화면에서 다시 누르면 전송.
- Backspace: 리뷰 화면에서 다시 찍기.
- Esc: 취소 또는 닫기.
- Tab / 1~9: 파트너 전환.
- 0 또는 A: 전체 파트너에게 동시 발송.
- 내 룸 > 초대링크 복사: 앱을 아직 설치하지 않은 상대에게 초대 링크를 보낸다.

## 자동 업데이트

Ping은 Sparkle로 업데이트를 확인한다. 새 버전이 공개되면 알림과 표준 업데이트 다이얼로그가 뜨고, 사용자가 승인하면 바로 다운로드/설치/재시작 흐름으로 진행된다.

## v0.3.25 수정

- 내 룸에서 화면+얼굴 메시지를 확대할 때 영상이 사라지던 문제를 수정했다.
- 확장된 화면+얼굴 영상은 사이드바 폭을 줄이지 않고 룸 매니저 최상위 레이어에서 사이드바 위로 표시된다.

## v0.3.24 수정

- 화면+얼굴 메시지의 우측 하단 얼굴 크기를 프리뷰와 실제 저장 영상에서 같은 비율로 유지하도록 수정했다.
- 내 룸 히스토리에서 화면+얼굴 메시지를 확대 재생할 때 사이드바 폭은 유지하고 영상이 사이드바 위로 확장되어 전체 화면이 잘리지 않게 했다.
- 발신자가 상대방의 로컬 저장 허용 여부를 제어하는 저장 권한 설정을 반영했다.

## v0.3.16 수정

- 내 룸 히스토리에서 타임스탬프 swipe reveal이 손을 떼면 자동으로 원위치로 돌아온다.
- 룸 매니저의 새 룸/룸 찾기 툴바 액션이 사이드바 상태와 무관하게 윈도우 우측에 고정된다.
- 룸 매니저 사이드바는 더 컴팩트한 폭을 기본으로 쓰고, 룸 이름은 16자로 제한된다.
- 히스토리 영상 썸네일과 인라인 재생이 로컬 sent/received 아카이브를 먼저 사용한다.

## v0.3.17 수정

- 트랙패드 타임스탬프 reveal이 손을 떼는 즉시 복귀하고 관성 스크롤에 끌려가지 않는다.
- reveal 중 타임스탬프는 말풍선과 함께 밀리지 않고 우측 고정 lane에 표시된다.
- reveal 이벤트가 수직 관성 스크롤을 가로채거나 reset 애니메이션을 반복 시작하지 않도록 해 룸 히스토리 렉을 줄였다.
- 히스토리 영상 인라인 플레이어가 고정 크기를 유지해 썸네일 클릭 후 영상 영역이 사라지지 않는다.
- 히스토리 영상 확장 크기를 키우고, 클릭 시 튀는 느낌 없이 그대로 커지는 ease-out 모션을 적용했다.
- 인라인 영상 레이어 업데이트가 메인 큐에 누적되지 않도록 bounds 변경 시에만 동기 갱신한다.
- 인라인 영상은 실제 표시 크기가 잡힌 뒤 0초부터 재생을 시작해 짧은 영상이 끝 프레임부터 보이지 않게 했다.
- trackpad release/cancel 이벤트가 delta 0으로 들어와도 타임스탬프 reveal을 즉시 닫는다.
- 룸 히스토리 창 기본 크기를 현재 QA에 맞춘 컴팩트한 폭과 높이로 조정했다.
- 마지막 메시지가 입력 필드에 붙지 않도록 히스토리 리스트 하단 여백을 확보했다.

## v0.3.21 수정

- 히스토리 영상 클릭 후 썸네일 영역이 비어 있고 재생이 시작되지 않던 회귀를 수정했다.
- 인라인 영상 플레이어는 SwiftUI 업데이트 호출이 아니라 AppKit view layout에서 layer 크기를 맞춘 뒤 0초부터 재생해, 영상 클릭 후 CPU가 100%로 도는 레이아웃 루프를 막는다.
- 3명 이상 룸에서는 상대가 보낸 영상 메시지에도 보낸 사람 닉네임을 표시한다.
- 다크모드 룸 히스토리에서 날짜 구간이 전체 폭 배경 바처럼 보이던 문제를 제거했다.
- 온보딩 권한 화면의 상단 헤더 위치와 progress 게이지를 고정하고, 권한 체크 UI를 더 컴팩트한 상태 중심 레이아웃으로 재구성했다.
- 화면 녹화 권한은 macOS 설정에서만 켤 수 있음을 명확히 표시하고, 알림 요청 창이 보이지 않을 때 시스템 설정 안내를 보여준다.

## v0.3.23 수정

- 온보딩 권한 화면에서 macOS 권한 재확인이 지연돼도 나머지 3~7단계 QA/설정을 계속 진행할 수 있게 했다.
- 릴리즈 앱의 ad-hoc designated requirement를 bundle id 기준으로 고정해 업데이트 후 TCC 권한 판정이 빌드 해시 변화에 흔들리지 않도록 했다.
- 카메라/마이크 권한 요청이 시스템 프롬프트 없이 멈추는 경우 버튼이 영구히 "확인 중"에 남지 않도록 timeout fallback을 추가했다.

## v0.3.22 수정

- 온보딩 화면 전환 시 상단 헤더와 progress 위치가 움직이지 않도록 고정 크기 레이아웃으로 정리했다.
- 권한 화면을 0/4 카운터와 긴 설명 없이 4개 항목만 보이는 미니멀 체크리스트로 단순화했다.
- 앱 시작 시 알림 권한 프롬프트를 먼저 소모하지 않도록 바꿔, 온보딩의 알림 `허용` 버튼이 실제 요청을 담당한다.
- 화면 녹화 권한 확인은 시스템 프롬프트를 띄우지 않는 CoreGraphics 사전 체크만 사용하고, macOS가 요구하는 앱 재시작 안내를 명확히 표시한다.

## 시스템 요구사항

- macOS 13 Ventura 이상
- Apple Silicon Mac 권장
