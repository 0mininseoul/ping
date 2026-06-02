# iOS / Apple Watch — App Store 심사 제출 체크리스트

마지막 업데이트: 2026-05-30. 대상: **PingMobile**(`com.youngminpark.ping.PingMobile`) + 내장 watchOS 앱(PingWatch).
TestFlight에 최신 빌드 **build 16**(버전 0.1.1) 업로드 완료. 아래는 App Store Connect(ASC) 웹에서 직접 해야 하는 액션이다 (대부분 웹 UI라 CLI로 대신 못 함).

준비된 자산:
- 개인정보 처리방침 URL: `https://0minping.vercel.app/privacy`
- 지원 URL: `https://0minping.vercel.app/support`
- 연락 이메일: `contact@ascentum.co.kr`
- Team ID: `878FAHTFQJ` · 수출규정: `ITSAppUsesNonExemptEncryption=false`(자동 통과)

---

## 0. 🚨 리뷰어 페어링 경로

폰 앱은 **Mac과 QR 페어링이 없으면 companion 안내 화면에서 막혀** 아무것도 못 한다.
이를 방지하기 위해 페어링 전 화면에서 companion 역할과 Mac 설치 경로를 직접 안내한다.
- 폰 앱은 Mac 데스크톱 앱과 연결해 사용하는 companion입니다.
- 페어링 전 화면은 `https://0minping.vercel.app`을 **Mac 앱 설치 페이지**로 표시하고, URL 열기/복사/공유와 **QR 스캔**을 제공합니다.
- **심사 진입 방법**: Mac에서 `https://0minping.vercel.app`을 열어 Ping Mac 앱을 설치한 뒤, Mac Ping > 설정 > 기기에서 QR을 표시하고 iPhone 앱에서 **QR 스캔**을 누른다.

---

## 1. ASC에서 앱 레코드 / 빌드 준비

App Store Connect → My Apps → Ping → (없으면 `+` 새 앱 생성: 플랫폼 iOS, 번들 ID `com.youngminpark.ping.PingMobile`, SKU 임의, 기본 언어 한국어).

- **빌드 선택**: 버전(0.1.1) → "빌드" 섹션에서 **build 16** 선택. (TestFlight 처리 완료 상태여야 함)
- watchOS 앱은 iOS 앱에 내장되어 자동 포함된다(별도 제출 아님).

---

## 2. App Information (앱 정보)

- **이름**: Ping
- **부제(Subtitle, 30자)**: `3초 영상 메시지`
- **카테고리**: 기본 = 소셜 네트워킹(Social Networking), 보조 = 라이프스타일(선택)
- **콘텐츠 권한**: 제3자 콘텐츠 없음
- **개인정보 처리방침 URL**: `https://0minping.vercel.app/privacy`

---

## 3. Pricing and Availability

- **가격**: 무료
- **국가/지역**: 전체(또는 대한민국부터)

---

## 4. 버전 메타데이터 (한국어, 붙여넣기용 초안)

**프로모션 텍스트(170자)**
```
짝과 3초 영상으로 안부를 전하세요. Mac·PC에서 짧게 찍어 보내면, iPhone과 Apple Watch로 바로 도착하고 받아쓰기로 답할 수 있어요.
```

**설명(Description)**
```
Ping은 가까운 사람과 3초 영상 메시지를 주고받는 가장 가벼운 방법입니다.

• Mac·Windows에서 단축키 한 번으로 3초 영상을 찍어 보냅니다.
• iPhone과 Apple Watch로 알림이 도착하고, 탭하면 바로 재생됩니다.
• 받아쓰기(음성)로 빠르게 텍스트 답장을 보낼 수 있습니다.

영상은 책상에서, 답장은 손안에서. 길게 쓰지 않아도 표정과 목소리로 안부가 전해집니다.

• 익명 계정 — 이메일·전화번호 없이 시작합니다.
• 영상 메시지는 약 7일 후 자동 삭제됩니다.
• 광고 없음, 데이터 판매 없음.

iPhone·Apple Watch 앱은 Mac/PC의 같은 계정을 QR로 연결해 사용하는 컴패니언입니다.
```

**키워드(100자, 쉼표 구분)**
```
영상메시지,3초,영상,메시지,커플,가족,친구,안부,음성,받아쓰기,푸시,워치,컴패니언,짧은영상
```

- **지원 URL**: `https://0minping.vercel.app/support`
- **마케팅 URL**(선택): `https://0minping.vercel.app`

---

## 5. 스크린샷 (필수)

- **iPhone 6.9"**(예: iPhone 16 Pro Max, 1320×2868) — 또는 6.5" — **최소 1장, 권장 3~5장**.
- **Apple Watch**(내장 워치앱 포함 시) — 워치 스크린샷이 요구될 수 있음(예: 49mm). 알림/재생 화면 1~3장.
- 생성 방법: 시뮬레이터(`xcrun simctl io booted screenshot`)로 각 화면 캡처하거나, 실기기 스크린샷.
- 추천 화면: ① "연결됐어요" 인박스, ② 룸 스레드(영상 썸네일+채팅), ③ 영상 풀스크린 재생, ④ 받아쓰기 답장.

---

## 6. App Privacy (개인정보 라벨)

ASC → App Privacy → "Get Started". 아래대로 신고(처리방침과 일치):

- **데이터 수집함: 예**
- 수집 항목:
  - **사용자 콘텐츠(User Content)** — 영상/사진/기타: ✅ "앱 기능(App Functionality)" 목적. 사용자에게 연결됨(Linked). 추적(Tracking) 아님.
  - **식별자(Identifiers)** — 기기 ID/푸시 토큰: ✅ "앱 기능" 목적. Linked. 추적 아님.
  - **사용 데이터(Usage Data)** 또는 **진단(Diagnostics)** — 익명 이벤트: ✅ "분석(Analytics)" 목적. **Not linked**(익명). 추적 아님.
- **이름/이메일/전화/연락처/위치/결제: 수집 안 함.**
- **광고/제3자 추적: 없음** (App Tracking Transparency 불필요).

---

## 7. 연령 등급 (Age Rating)

- 설문에서 대부분 "없음/드물게"가 아닌 **모두 없음**으로 답. 사용자 생성 콘텐츠(메시지)가 있으나 1:1/소규모 비공개 → "Unrestricted Web Access: No". 예상 등급 **4+ ~ 12+** 수준.

---

## 8. App Review Information (심사용 정보)

- **연락처**: 이름/전화/이메일(`contact@ascentum.co.kr`).
- **데모 계정**: 계정 정보 불필요. Mac 앱과 iPhone 앱은 QR 페어링으로 같은 익명 계정에 연결된다.
- **노트(영문, 붙여넣기용 초안)**:
```
Ping is a companion to our macOS desktop app. A 3-second video is recorded on the desktop and delivered to the paired iPhone/Apple Watch, where the user views it and replies with dictated text. The iPhone app links to the same anonymous account on the desktop via a QR code (Settings > Devices in the desktop app); there is no email/password sign-up.

The unpaired screen explains that the iPhone app connects to Ping for Mac. It shows the Mac app install page (https://0minping.vercel.app) as a tappable link with copy/share controls, followed by a QR scan action. Please install the Mac app, open Mac Ping > Settings > Devices, show the QR code, and scan it from the iPhone app.

Video messages auto-delete after ~7 days. No ads, no third-party tracking.
```

---

## 9. 제출

- 모든 섹션 녹색 체크 → 우상단 **"Add for Review" / "Submit for Review"**.
- 수출규정: 코드에 `ITSAppUsesNonExemptEncryption=false`가 있어 자동 통과(추가 질문 없음).
- 심사 ~24–48시간. 거절 시 Resolution Center 회신으로 0번/8번 내용 보강.

---

## 빠른 요약 (해야 할 일 순서)
1. **0번 페어링 경로 구현 완료** (페어링 전 화면에서 Mac 앱 설치 페이지와 QR 스캔 제공).
2. 스크린샷 생성(iPhone 6.9" + 워치).
3. ASC에서 2~8번 메타데이터/Privacy/연령/리뷰노트 입력 + build 16 선택.
4. **Submit for Review**.
