# macOS APNs 및 대형 화면+얼굴 재생 구현 계획

> **에이전트 작업자용:** 필수 하위 스킬로 `superpowers:subagent-driven-development`(권장) 또는 `superpowers:executing-plans`를 사용해 이 계획을 Task별로 구현한다. 진행 추적에는 체크박스(`- [ ]`) 문법을 사용한다.

**목표:** macOS 영상, 채팅, 초대 배너를 presence 기반 Mac/iPhone/Watch 라우팅을 사용하는 APNs로 전환하고, 자동 얼굴 회신을 실행 중에만 유지하며, 룸 히스토리의 화면+얼굴 영상을 600포인트 floating 플레이어로 연다.

**아키텍처:** 두 번째 백엔드를 추가하지 않고 기존 Supabase 기기 토큰 스키마와 Vercel APNs 제공자를 확장한다. Mac은 production/development APNs 토큰을 등록하고 Realtime은 상태와 자동 회신 작업에만 유지하며, 사용자에게 보이는 이벤트 알림은 APNs만 담당한다. 창 내부 화면+얼굴 overlay는 책임이 분리된 AppKit 창 컨트롤러로 교체한다.

**기술 스택:** Swift 6, AppKit, UserNotifications, Supabase Postgres/RLS/RPC/Database Webhooks, TypeScript/Vitest, Vercel Node Functions, APNs HTTP/2, XcodeGen.

---

### Task 1: 기기 토큰 데이터베이스 계약 확장

**파일:**
- 생성: `./scripts/supabase-ping.sh migration new macos_apns_device_tokens`가 출력한 정확한 `supabase/migrations/*_macos_apns_device_tokens.sql` 경로
- 수정: `supabase/tests/device_tokens_test.sql`

- [ ] **Step 1: 보호된 CLI로 마이그레이션 생성**

`./scripts/supabase-ping.sh migration new macos_apns_device_tokens`를 실행하고 생성된 경로를 사용한다. timestamp를 임의로 만들지 않는다.

- [ ] **Step 2: 실패하는 pgTAP 검증 추가**

`macos`와 `sound_preference`를 허용하고, 잘못된 플랫폼/소리를 거부하고, 두 번째 인증 UID가 같은 플랫폼/토큰을 등록하면 두 행이 남지 않고 소유권이 이전되는지 검증한다.

```sql
select lives_ok(
  $$ select public.ping_register_device_token('mac-token', 'macos', 'production', 'none') $$,
  'macOS production token can be registered'
);
select is(
  (select count(*)::int from public.device_tokens where token = 'mac-token'),
  1,
  'one APNs token has one owner'
);
```

- [ ] **Step 3: SQL 테스트를 실행해 실패 확인**

`./scripts/supabase-ping.sh test --help`로 기존 명령을 찾은 뒤 데이터베이스 테스트 모음을 실행한다. 예상: `macos`, `sound_preference`, 네 인자 RPC가 없어 실패한다.

- [ ] **Step 4: 마이그레이션 구현**

플랫폼 check를 교체하고, `sound_preference text not null default 'default'`를 추가하고, `(platform, token)` 전역 unique index를 만들고, 등록 RPC를 다음 계약으로 교체한다.

```sql
create or replace function public.ping_register_device_token(
    token_text text,
    platform_text text,
    environment_text text default 'production',
    sound_preference_text text default 'default'
) returns void
```

security-definer 본문은 기존 인증 UID guard를 호출하고, enum 형태 입력을 모두 검증하고, 다른 UID가 가진 동일 `(platform, token)` 행을 지운 뒤 현재 UID로 upsert해야 한다. 예전 세 인자 overload의 권한을 제거한 뒤 네 인자 함수를 `authenticated`에 grant한다.

- [ ] **Step 5: 로컬 검증 및 가능한 경우 database advisor 실행**

SQL 모음, `./scripts/supabase-ping.sh migration list --local`, `--help`로 확인한 wrapper 지원 advisor 명령을 실행한다. 예상: 테스트 통과, 새 보안 경고 없음.

- [ ] **Step 6: 커밋**

```bash
git add supabase/migrations supabase/tests/device_tokens_test.sql
git commit -m "feat(push): support macOS APNs device tokens"
```

### Task 2: 플랫폼 인식 Vercel 라우팅과 초대 푸시 구현

**파일:**
- 수정: `api/_lib/webhook.ts`
- 수정: `api/_lib/payload.ts`
- 생성: `api/_lib/routing.ts`
- 수정: `api/push.ts`
- 수정: `api/_lib/__tests__/webhook.test.ts`
- 수정: `api/_lib/__tests__/payload.test.ts`
- 생성: `api/_lib/__tests__/routing.test.ts`
- 수정: `api/_lib/__tests__/push.test.ts`

- [ ] **Step 1: 실패하는 parser, payload, routing 테스트 작성**

`invitations` INSERT와 정확한 대상 행렬을 검증한다.

```ts
expect(selectPushTokens(tokens, true).map(t => t.platform)).toEqual(['macos']);
expect(selectPushTokens(tokens, false).map(t => t.platform)).toEqual(['ios', 'watchos']);
expect(selectPushTokens([macToken], false)).toEqual([macToken]);
```

macOS payload category/식별자 키, 모바일 영상 signed URL, `none` 토큰의 소리 생략, 플랫폼별 APNs topic도 검증한다.

- [ ] **Step 2: 집중 Vitest 파일을 실행해 실패 확인**

`npm test -- --run api/_lib/__tests__/routing.test.ts api/_lib/__tests__/push.test.ts api/_lib/__tests__/webhook.test.ts api/_lib/__tests__/payload.test.ts`를 실행한다. 예상: invitation parser와 routing export가 없어 실패한다.

- [ ] **Step 3: 책임이 분리된 routing 타입과 로직 추가**

UID, 플랫폼, 환경, 소리 설정을 가진 토큰을 정의한다. Supabase/APNs 의존성 없이 `routing.ts`에 승인된 배타적 계약을 구현한다.

```ts
export type PushPlatform = 'macos' | 'ios' | 'watchos';
export function selectPushTokens(tokens: DeviceToken[], hasLiveMac: boolean): DeviceToken[]
```

- [ ] **Step 4: 초대 parsing과 플랫폼 payload builder 추가**

`id`, `to_uid`, `room_id`, `from_nickname`, `room_name`을 parse한다. 기존 `PING_MESSAGE` 모바일 계약과 signed URL을 유지하면서 `LocalNotificationCenter.Category`와 호환되는 macOS category를 만든다.

- [ ] **Step 5: `handlePush`를 수신자 batch 중심으로 리팩터링**

`device_tokens`에서 `uid, token, platform, environment, sound_preference`를 조회한다. 각 영상 수신자, 채팅 룸 멤버, 초대 수신자마다 live presence를 조회하고 토큰을 선택하고, 선택된 모바일 토큰이 필요할 때만 signed 영상 URL을 만들고 다음 매핑의 topic으로 APNs를 호출한다.

```ts
bundleIds: {
  macos: process.env.APNS_MACOS_BUNDLE_ID,
  ios: process.env.APNS_IOS_BUNDLE_ID,
  watchos: process.env.APNS_WATCHOS_BUNDLE_ID ?? process.env.APNS_IOS_BUNDLE_ID,
}
```

시크릿 검증, collapse ID, 410 정리, 제한된 로그, eligible 토큰이 없는 인식 가능한 이벤트의 200 응답을 유지한다.

- [ ] **Step 6: 전체 TypeScript 모음 실행**

`npm test`를 실행한다. 예상: 모든 Vitest 통과.

- [ ] **Step 7: 커밋**

```bash
git add api
git commit -m "feat(push): route macOS mobile and invite notifications"
```

### Task 3: Mac 앱 APNs 등록 및 원격 액션 라우팅

**파일:**
- 생성: `Ping/Notifications/RemotePushRegistrar.swift`
- 수정: `Ping/AppDelegate.swift`
- 수정: `Ping/Notifications/LocalNotificationCenter.swift`
- 수정: `Ping/UI/Setup/SettingsScene.swift`
- 수정: `project.yml`
- 수정: `Ping.entitlements`
- 수정: `PingDebug.entitlements`
- 생성: `PingTests/RemotePushContractTests.swift`

- [ ] **Step 1: 실패하는 Swift 계약 테스트 추가**

registrar가 `macos`, 현재 APNs 환경, 현재 소리 설정으로 `ping_register_device_token`을 호출하는지, `AppDelegate`가 등록 성공/실패를 전달하는지, 원격 payload가 기존 영상/채팅/초대 처리기를 쓰는지, project entitlement가 macOS 13/Swift 6을 바꾸지 않고 macOS APNs 환경을 선언하는지 검증한다.

- [ ] **Step 2: 집중 테스트 실행해 실패 확인**

`xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" -only-testing:PingTests/RemotePushContractTests test`를 실행한다. 예상: registrar 소스와 callback이 없어 실패한다.

- [ ] **Step 3: `RemotePushRegistrar` 구현**

`@MainActor`로 만들고, 현재 토큰을 메모리에 보관하고, 알림 승인 뒤 `NSApp.registerForRemoteNotifications()`를 호출하고, bootstrap/계정 변경/네트워크 복구 뒤 backend 등록을 재시도한다.

```swift
func update(deviceToken: Data)
func registerIfPossible(uid: String) async
func refreshSoundPreference(uid: String) async
```

토큰을 hex로 인코딩하고 Debug에서는 `sandbox`, Release에서는 `production`을 고르고, 네 개 SQL named argument로 `SupabaseClient.rpcVoid`를 호출한다.

- [ ] **Step 4: AppDelegate callback과 계정 수명주기 연결**

`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`와 실패 callback을 구현한다. bootstrap 성공 뒤와 계정 전환 뒤 등록한다. 원시 APNs 토큰을 UserDefaults나 Keychain에 저장하지 않는다.

- [ ] **Step 5: 현재 알림 delegate를 원격 payload에 재사용**

하나의 parsing helper에서 원격/로컬 식별자 키를 정규화한다. `willPresent([.banner, .sound])`, 초대 액션, 채팅 룸 focus, 영상 재생, Sparkle 업데이트 액션을 유지한다.

- [ ] **Step 6: 프로젝트 재생성 및 테스트**

`xcodegen generate`, 집중 테스트, 전체 macOS 테스트 모음을 실행한다. 예상: 통과.

- [ ] **Step 7: 커밋**

```bash
git add Ping project.yml Ping.entitlements PingDebug.entitlements PingTests/RemotePushContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): register and handle APNs notifications"
```

### Task 4: 실행 중 자동 회신을 유지하며 이벤트 로컬 배너 제거

**파일:**
- 수정: `Ping/AppDelegate.swift`
- 수정: `Ping/Notifications/LocalNotificationCenter.swift`
- 수정: `PingTests/AutoFaceReplyContractTests.swift`
- 생성: `PingTests/PushOnlyNotificationContractTests.swift`

- [ ] **Step 1: push-only 이벤트 알림 실패 테스트 추가**

초대, 채팅, 채팅 catch-up, 영상 observer 경로가 `UNUserNotificationCenter.add`를 호출하지 않는지 검증한다. Sparkle 업데이트 알림 코드는 남아 있고 영상 전달이 행을 notified 처리하기 전에 `autoFaceReply.handleIncoming`을 호출하는지도 검증한다.

- [ ] **Step 2: 집중 테스트를 실행해 현재 로컬 호출 확인**

두 집중 테스트 class를 실행한다. 예상: `notifyIncomingMessage`, `notifyIncomingChat`, `notifyChatCatchUp`, `notifyIncomingInvitation` 호출 때문에 실패한다.

- [ ] **Step 3: 이벤트 처리와 알림 표시 분리**

네 사용자 이벤트 예약 메서드를 제거하거나 production 경로에서 사용할 수 없게 한다. 초대 observer는 상태만 갱신한다. Chat Realtime은 히스토리만 갱신한다. 영상 observer는 실행 중 자동 회신 처리, polling 중복 제거용 서버 행 notified 처리, 기존 설정에 따른 prefetch/autoplay는 수행할 수 있지만 배너는 절대 만들지 않는다.

- [ ] **Step 4: cold-start push 처리의 자동 회신 차단**

`appStartTime` freshness 검사를 유지하고, 필요하면 명시적 source gate를 더해 알림 응답 조회가 자동 회신 coordinator로 들어갈 수 없게 한다.

- [ ] **Step 5: 집중/전체 macOS 테스트 실행**

예상: 이벤트 로컬 알림 테스트 통과, 자동 회신 loop/freshness 테스트 green, Sparkle 테스트 green.

- [ ] **Step 6: 커밋**

```bash
git add Ping/AppDelegate.swift Ping/Notifications/LocalNotificationCenter.swift PingTests
git commit -m "refactor(macos): use APNs as the only event banner path"
```

### Task 5: 600포인트 floating 화면+얼굴 히스토리 플레이어 추가

**파일:**
- 생성: `Ping/UI/History/ScreenFacePlaybackWindow.swift`
- 수정: `Ping/UI/History/HistoryView.swift`
- 수정: `Ping/UI/Setup/RoomManagerWindow.swift`
- 수정: `Ping/UI/History/RoomTimelineView.swift`
- 수정: `Ping/UI/History/MessageRowView.swift`
- 삭제: `Ping/UI/History/ScreenFaceExpansionOverlay.swift`
- 수정: `PingTests/RoomManagerUXContractTests.swift`

- [ ] **Step 1: 실패하는 크기/수명주기 테스트 작성**

600포인트 목표, 화면 비율 `0.5...3.0` clamp, 32포인트 화면 여백, 비례 축소를 순수 sizing helper로 테스트한다. 계약 테스트는 별도 AppKit 창, 같은 메시지 toggle, 방 변경 시 닫기, Escape 닫기, Enter 다시 재생을 요구한다.

```swift
XCTAssertEqual(ScreenFacePlaybackSizing.size(aspectRatio: 16.0 / 9.0, visibleFrame: largeFrame).width, 600)
```

- [ ] **Step 2: 집중 테스트를 실행해 실패 확인**

`PingTests/RoomManagerUXContractTests`를 실행한다. 예상: floating player type이 없고 기존 420포인트 overlay가 남아 있어 실패한다.

- [ ] **Step 3: 책임이 분리된 창 구현**

600포인트 콘텐츠 목표, aspect-fit `AVPlayerLayer`, visible-frame clamp, 룸 창 중심 배치, Escape 닫기, Enter 다시 재생을 가진 borderless floating `NSWindow`를 만든다. 재생 전 cached/downloaded 파일을 resolve하거나 전용 SwiftUI loading view를 hosting해 기존 로딩/오류 동작을 유지한다.

- [ ] **Step 4: overlay 상태를 창 소유권으로 교체**

룸 매니저/히스토리 root가 플레이어 창 하나를 소유한다. 화면+얼굴 메시지를 클릭하면 열거나 toggle하고, 다른 방을 고르거나 부모를 닫으면 닫는다. 얼굴 전용 메시지는 인라인으로 유지한다. spacer/reporter 우회와 obsolete overlay 소스를 제거한다.

- [ ] **Step 5: 집중/전체 macOS 테스트 실행**

예상: 600포인트 크기/수명주기 검증 통과, 기존 히스토리 테스트 모두 green.

- [ ] **Step 6: 커밋**

```bash
git add Ping/UI/History Ping/UI/Setup/RoomManagerWindow.swift PingTests/RoomManagerUXContractTests.swift
git commit -m "feat(history): open screen recordings in a 600pt player"
```

### Task 6: 서명, 릴리즈 검증, 운영 문서 강화

**파일:**
- 수정: `scripts/build-release.sh`
- 수정: `docs/PUSH_BACKEND_SETUP.md`
- 수정: `PING_PROJECT_SPECIFICATION.md`
- 수정: `README.md`
- 생성: `PingTests/MacPushReleaseContractTests.swift`

- [ ] **Step 1: 실패하는 릴리즈 계약 테스트 추가**

릴리즈 스크립트가 명시적 provisioning-profile 경로를 받아 `Contents/embedded.provisionprofile`로 포함하고, 최종 서명 앱 entitlement를 검사하고, `com.apple.developer.aps-environment`가 production이 아니면 거부하도록 요구한다.

- [ ] **Step 2: 릴리즈 검사 구현**

바깥 앱 서명 전에 검증된 profile을 복사한다. 서명 후 다음을 실행한다.

```bash
codesign -d --entitlements :- "$APP" > "$TMP_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' "$TMP_ENTITLEMENTS"
```

값이 `production`이 아니거나 embedded profile이 없거나 일반 codesign 검증이 실패하면 종료한다. 기존 공증은 바꾸지 않는다.

- [ ] **Step 3: 제품/운영 문서 동기화**

제품 명세에 APNs-only 영상/채팅/초대 배너, 정확한 라우팅, 실행 중 자동 회신, 600포인트 floating 재생을 반영한다. 백엔드 설정 문서에 `APNS_MACOS_BUNDLE_ID`, `APNS_IOS_BUNDLE_ID`, 선택적 watch topic, invitations webhook, production smoke 절차를 반영한다. README의 새 동작과 충돌하는 설명을 제거한다.

- [ ] **Step 4: 문서/릴리즈 계약 테스트 실행**

집중 Swift 테스트와 `git diff --check`를 실행한다. 예상: 통과하고 강제/offline 자동 회신 또는 로컬 이벤트 알림이라는 오래된 설명이 없다.

- [ ] **Step 5: 커밋**

```bash
git add scripts/build-release.sh docs/PUSH_BACKEND_SETUP.md PING_PROJECT_SPECIFICATION.md README.md PingTests/MacPushReleaseContractTests.swift
git commit -m "docs(push): document macOS APNs deployment"
```

### Task 7: 통합 시스템 적용 및 검증

**파일:**
- 검증이 위 파일의 결함을 드러낼 때만 수정한다.

- [ ] **Step 1: 모든 로컬 검증 실행**

`npm test`, `swift test --package-path PingKit`, `xcodegen generate`, 전체 macOS `xcodebuild test`, Debug build를 실행한다. 예상: 모두 통과.

- [ ] **Step 2: pinned wrapper로 마이그레이션 적용**

`./scripts/supabase-ping.sh projects list`를 실행해 ref `qxjtprxvjmaxlbtljcjw`를 확인한 뒤 `./scripts/supabase-ping.sh db push`를 실행한다. 새 constraint/function signature를 조회하고 advisor를 실행한다. 다른 프로젝트나 raw access token을 쓰지 말고 멈춘다.

- [ ] **Step 3: Vercel 환경변수 이름 갱신 및 배포**

값을 출력하지 않고 기존 secret을 확인하고, macOS/iOS topic 환경변수 이름을 추가하고, production에 배포하고, `/api/health`, 잘못된 secret 401, 토큰 없는 인식 가능한 이벤트를 검증한다. Hobby 비상업 제약을 문서에 유지한다.

- [ ] **Step 4: invitations INSERT webhook 설정**

`messages`, `chat_messages`, `invitations` INSERT가 같은 endpoint와 공유 secret으로 도착하게 한다. UPDATE/DELETE 동작은 바꾸지 않는다.

- [ ] **Step 5: production APNs smoke test 수행**

Mac 실행(Mac만), Mac 종료+모바일 설치(모바일만), Mac 종료+모바일 없음(Mac만)에서 영상/채팅/초대를 검증한다. push 클릭, 초대 액션, 이벤트 로컬 중복 없음, 실행 중 자동 회신, 600포인트 재생을 확인한다.

- [ ] **Step 6: 최종 상태 및 커밋**

`git status --short`, `git log --oneline -8`, `git diff --check`를 실행한다. 검증 수정이 필요했다면 범위에 맞는 conventional commit으로 커밋한다. 완료하지 못한 외부 Apple provisioning 또는 기기 matrix 단계는 통과했다고 주장하지 않고 보고한다.
