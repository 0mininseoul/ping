# macOS APNs 알림 및 대형 화면+얼굴 재생 설계

- 작성일: 2026-09-17
- 상태: 구현 승인됨
- 범위: macOS 원격 알림, 기존 iPhone/Watch 라우팅, 앱 실행 중에만 동작하는 자동 얼굴 회신, 룸 히스토리의 화면+얼굴 재생 크기

## 1. 목표

1. 영상, 채팅, 룸 초대 알림을 macOS가 예약하는 로컬 알림 대신 APNs로 전달한다.
2. Mac 앱이 실행되지 않을 때도 알림을 전달하면서 기존 iPhone/Watch 동반 앱 동작을 유지한다.
3. Mac 프로세스가 이미 실행 중이고 새 영상 이벤트를 실시간으로 받았을 때만 자동 얼굴 회신을 실행한다.
4. 창 내부의 기존 420포인트 화면+얼굴 확대를 기본 500포인트 룸 창보다 넓은 600포인트 floating 재생창으로 교체한다.

Sparkle 업데이트 알림은 Supabase 이벤트가 아니라 기기 자체에서 발생하므로 로컬 알림으로 유지한다. Windows 알림 동작은 범위 밖이다.

## 2. 라우팅 계약

수신자별 라우팅은 배타적이다.

| 수신자 상태 | APNs 대상 |
|---|---|
| 하나 이상의 Mac presence가 실행 중 | macOS 토큰만 |
| 실행 중인 Mac 없음, iOS/watchOS 토큰 있음 | iOS/watchOS 토큰만 |
| 실행 중인 Mac 없음, iOS/watchOS 토큰 없음 | macOS 토큰만 |

실행 중인 Mac presence는 종료 표시가 없고 기존 45초 TTL 안에 갱신된 `desktop_presence` 행이다. 등록된 macOS 토큰은 앱 종료 후에도 남아 APNs가 앱 프로세스 없이 알림을 표시할 수 있게 한다.

## 3. 아키텍처

기존 Supabase Database Webhook과 Vercel Hobby Node 함수 `api/push.ts`를 유일한 푸시 제공자로 유지한다. 이 함수는 `messages`, `chat_messages`, `invitations` INSERT를 처리하고, 웹훅 시크릿을 검증하고, 수신자를 판별하고, presence와 기기 토큰을 읽고, 라우팅 계약으로 대상 플랫폼을 고른 뒤 APNs 요청을 전송한다.

기존 APNs 키를 재사용한다. 제공자는 단일 전역 bundle ID 대신 플랫폼별 topic을 매핑한다. macOS는 `com.youngminpark.ping.Ping`을 쓰고, iOS/watchOS는 기존 topic과 payload 계약을 유지한다. APNs 자격 증명, topic, Supabase service-role 키, 웹훅 시크릿은 Vercel 환경변수에만 둔다.

macOS 앱은 매번 실행할 때 `NSApplication.registerForRemoteNotifications()`로 APNs에 등록한다. Supabase bootstrap 뒤 토큰을 활성 익명 계정에 `platform = macos`로 등록한다. 계정 전환 시 토큰을 새 UID로 이전해 한 기기가 이전 계정의 알림을 계속 받지 않게 한다.

## 4. 데이터베이스 계약

`device_tokens`는 `ios`, `watchos`에 더해 `macos`를 허용한다. 토큰은 현재 UID 하나에만 속한다. `ping_register_device_token`은 플랫폼과 환경을 검증하고, 같은 플랫폼/토큰의 오래된 소유권을 제거한 뒤 인증된 UID로 upsert한다. RLS는 클라이언트가 자기 행만 읽고 제거하도록 계속 제한하고, Vercel service-role 클라이언트가 제공자 측 fan-out을 수행한다.

macOS 토큰은 로컬 알림 소리 설정(`default` 또는 `none`)을 저장한다. 설정이 바뀌면 토큰을 다시 등록해 값을 갱신한다. 모바일 토큰은 기존 기본 소리 동작을 유지한다.

service-role 자격 증명이나 APNs 키는 어떤 클라이언트에도 포함하지 않는다.

## 5. 알림 payload와 액션

- 영상: 메시지 ID, 룸 ID, 발신자 표시 이름, 기존 영상 알림 category.
- 채팅: 채팅 ID, 룸 ID, 발신자 표시 이름, 길이가 제한된 미리보기.
- 초대: 초대 ID, 룸 ID/이름, 초대한 사람 표시 이름, 수락/거절 액션.

macOS payload에는 식별자와 표시용 메타데이터만 넣는다. 클릭 뒤 인증된 클라이언트가 권위 있는 데이터를 조회한다. 기존 iPhone 영상 푸시에는 Notification Service Extension에 필요한 단기 signed URL을 계속 포함한다.

Mac 앱이 활성 상태이면 `UNUserNotificationCenterDelegate.willPresent`가 원격 배너와 소리를 표시한다. 앱이 실행되지 않으면 macOS가 알림을 직접 표시한다. cold start 알림을 클릭하면 현재와 동일한 영상, 채팅, 초대 처리기로 연결한다.

APNs collapse ID에는 이벤트 행 ID를 사용한다. `410 Unregistered` 토큰은 제거한다. 다른 제공자 오류는 기록하고 로컬 알림으로 몰래 우회하지 않는다.

## 6. 로컬 처리와 자동 얼굴 회신

Realtime과 polling은 룸 상태, 히스토리 갱신, 실행 중 자동 얼굴 회신을 위해 유지한다. 영상, 채팅, 초대에 대한 로컬 알림을 예약해서는 안 된다.

프로세스 실행 중 받은 영상 이벤트에는 기존 자동 회신 안전 정책을 적용한다. 현재 앱 시작 전 생성된 메시지, catch-up 행, 자동 회신 메시지, 오래된 메시지, 카메라를 사용할 수 없는 경우에는 절대 회신하지 않는다. 원격 알림 수신이나 클릭 자체가 자동 회신을 시작해서는 안 된다.

클라이언트는 실시간/catch-up 행 처리 후 polling 중복 제거를 위해 영상 알림 행을 소비 처리할 수 있지만, 사용자에게 보이는 배너는 APNs만 제공한다.

## 7. 서명과 배포

macOS App ID에 Push Notifications를 활성화해야 한다. Debug 빌드는 development APNs 환경, Release 빌드는 production 환경을 사용한다. Developer ID 릴리즈에는 `com.apple.developer.aps-environment`를 허용하는 provisioning profile을 포함하고, 기존 Developer ID 서명, hardened runtime, 공증, staple을 유지한다.

릴리즈 스크립트는 공증 전에 포함된 provisioning profile과 production APNs entitlement를 검증한다. 푸시 서명이 누락되거나 잘못되면 APNs 등록이 불가능한 앱을 배포하지 않고 릴리즈를 실패시킨다.

Ping은 비상업 개인 프로젝트이고 예상 호출량이 포함 한도 안이므로 Vercel Hobby를 사용한다.

## 8. 화면+얼굴 재생

룸에서 화면+얼굴 영상을 클릭하면 기존 420포인트 SwiftUI overlay 대신 별도 floating 재생창을 연다. 목표 콘텐츠 폭은 600포인트다. 저장된 화면 비율을 제한된 유효 범위에서 사용해 높이를 계산한다. 디스플레이가 32포인트 여백과 함께 목표 크기를 담을 수 없을 때만 visible frame에 맞춰 비례 축소한다.

재생창은 룸 창 중앙 위에 배치한 뒤 활성 화면 안으로 clamp한다. 룸이나 사이드바 크기를 바꾸지 않고 그 위에 떠 있어야 한다. 같은 메시지를 다시 클릭하거나, 다른 룸을 선택하거나, 룸 창을 닫거나, Escape를 누르면 닫는다. Enter는 영상을 처음부터 다시 재생한다. 얼굴 전용 원형 인라인 재생은 바꾸지 않는다.

## 9. 실패 처리

- 알림 권한 거부: 설정/온보딩의 기존 복구 경로를 표시하고, 권한 승인 뒤 APNs 등록을 다시 시도한다.
- 토큰 등록 실패: 기록하고 다음 네트워크 복구, 계정 bootstrap, 앱 실행 때 다시 시도한다.
- 웹훅/제공자 실패: 실패를 기록하고 로컬 알림 fallback을 만들지 않는다.
- 유효하지 않거나 오래된 push payload: 안전하게 무시하고 가능하면 룸 상태를 새로고침한다.
- 재생 다운로드 실패: floating 창에서 기존 인라인 오류 문구를 유지한다.

## 10. 인수 조건

1. macOS의 영상, 채팅, 초대 배너는 APNs로만 전달된다.
2. 실행 중인 Mac presence가 있으면 macOS 토큰만 푸시를 받는다.
3. 실행 중인 Mac이 없고 모바일 토큰이 하나 이상 있으면 iOS/watchOS 토큰만 푸시를 받는다.
4. 실행 중인 Mac과 모바일 토큰이 모두 없으면 Ping이 실행되지 않아도 macOS 토큰이 푸시를 받는다.
5. 기존 iPhone/Watch payload 동작이 계속 작동한다.
6. 이미 실행 중인 Mac 앱이 새 영상 이벤트를 받았을 때만 자동 얼굴 회신이 발생한다.
7. macOS 계정 전환 뒤 이전 계정 알림이 유출되지 않는다.
8. production macOS APNs entitlement와 provisioning profile이 없는 빌드는 릴리즈 검증에서 거부된다.
9. 룸 히스토리의 화면+얼굴 재생은 600포인트 floating 창으로 열리고, 화면 비율을 유지하고, 기본 룸 창 폭보다 넓고, 화면 밖으로 나가지 않는다.
10. 얼굴 전용 재생과 Sparkle 로컬 업데이트 알림은 그대로 유지된다.

## 11. 검증

- TypeScript 단위 테스트는 세 이벤트, 세 라우팅 상태, 플랫폼 topic, 소리 메타데이터, signed URL 유지, 토큰 정리를 검증한다.
- SQL 테스트는 macOS 플랫폼 허용, 토큰 소유권 이전, 유효성 검사, RLS 격리를 검증한다.
- Swift 테스트는 APNs 등록 흐름, payload 액션 라우팅, 로컬 이벤트 알림 제거, 실행 중에만 동작하는 자동 회신을 검증한다.
- UI 테스트는 600포인트 크기, 화면 비율 유지, visible frame clamp, 닫기/다시 재생 동작을 검증한다.
- 실제 production APNs 수동 smoke test는 Mac 실행, 모바일이 설치된 상태에서 Mac 종료, 모바일이 없는 상태에서 Mac 종료 각각에 대해 영상/채팅/초대를 검증한다.
