# Apple Watch 푸시 — 당신이 직접 해야 할 일 (쉬운 가이드)

코드/백엔드는 제가 합니다. 아래는 **물리 기기·Apple 포털·대시보드 권한**이 필요해 제가 대신 못 하는 것들입니다.

## ✅ 이미 끝낸 것 (당신이 해줬거나 제가 처리)
- Apple Developer Program 가입
- APNs `.p8` 키 생성 + Key ID/Team ID 제공
- Vercel 환경변수 7개(SUPABASE_URL/SERVICE_ROLE, APNs 키 3종, webhook secret, bundle id)
- Supabase Database Webhook(`ping_push`) 생성
- `device_tokens` 마이그레이션 원격 적용
- 백엔드 파이프라인 프로덕션 검증(`200 {sent:0}`)

## 🔲 지금/곧 해야 할 것

### 1. Supabase: refresh token 회전 끄기 (중요)
폰과 데스크톱이 **같은 익명 세션**을 공유하므로, 토큰 회전이 켜져 있으면 한쪽이 갱신할 때 다른 쪽이 로그아웃됩니다.
- Supabase Dashboard → **Authentication → Sessions(또는 Settings)** → "Refresh token rotation" **끄기**, 또는 "Reuse interval"을 크게(예: 86400초) 설정.
- 2인 규모에선 안전한 트레이드오프입니다.

### 2. watchOS 플랫폼 설치 (진행 중)
- Xcode → Settings → Components → **watchOS** 설치. (이게 끝나야 제가 워치 앱을 빌드·검증합니다.)

## 🔲 P6 단계 — 실제 기기 테스트 (TestFlight)

> 이 단계는 **당신의 iPhone + Apple Watch + App Store Connect**가 꼭 필요합니다.

### 3. App ID / 권한 (대부분 Xcode 자동 서명이 처리)
- Xcode에서 `Ping.xcodeproj` 열기 → **PingMobile**, **PingPushService**(그리고 워치 앱) 타깃의 *Signing & Capabilities*:
  - **Team** 선택(당신 개발자 계정).
  - **Automatically manage signing** 켜기.
  - PingMobile에 **Push Notifications** capability 추가(이미 entitlement에 `aps-environment` 있음).

### 4. App Store Connect에 앱 등록
- https://appstoreconnect.apple.com → **My Apps → +** → 새 앱:
  - Platform: iOS, Bundle ID: `com.youngminpark.ping.PingMobile`.

### 5. 빌드 업로드
- Xcode → 상단 디바이스를 **Any iOS Device** 선택 → **Product → Archive** → Organizer에서 **Distribute App → TestFlight & App Store** 업로드.

### 6. TestFlight 초대 + 설치
- App Store Connect → TestFlight → 본인 + 파트너를 테스터로 초대.
- 두 사람 모두 iPhone에 TestFlight로 설치, **Apple Watch 페어링**(워치 앱 자동 설치).

### 7. 페어링 (앱 안에서)
- Mac의 Ping → **설정 → 기기 탭**의 QR을, iPhone Ping 앱의 **"Mac QR 스캔"**으로 스캔 → "연결됨" 표시 확인.
- (스캔 즉시 이 폰의 APNs 토큰이 등록됩니다.)

### 8. 최종 테스트
- 상대(또는 다른 기기)가 데스크톱에서 **ping 영상 전송** → 당신 iPhone/Apple Watch에 **푸시 도착** → 탭하면 **3초 영상 재생** → **받아쓰기로 답장** → Mac 룸 chat에 들어오는지 확인.

## 제가 처리할 나머지
- P5 watchOS 앱 코드(설치 끝나면 빌드·검증).
- 실제 전송 전 Vercel **재배포 1회**(APNS_BUNDLE_ID 반영) — 제가 합니다.
- 막히는 빌드/서명 에러는 알려주시면 제가 대응.

## ⚠️ 보안 리마인더
- 채팅에 공유한 **Supabase PAT는 회전(삭제)** 권장: https://supabase.com/dashboard/account/tokens
