# Apple Watch 푸시 수신 + STT 답장 — Feasibility & Design 문서

- **작성일**: 2026-05-29
- **상태**: 설계·타당성(feasibility) — 구현 전. 본 문서 승인 후 writing-plans로 구현 플랜 작성.
- **범위 산정 근거**: 브레인스토밍 세션에서 사용자와 확정한 결정 로그(아래 §2).

---

## 1. 목표와 범위

파트너가 보낸 **3초 ping 영상 메시지**를 사용자의 **Apple Watch에서 푸시 알림으로 받고**, 워치에서 **바로 영상을 조회**하고, **STT(받아쓰기) 텍스트로 답장**할 수 있게 한다.

이 문서는 "할 수 있는가"에 답하고, "어떻게/얼마의 비용·난이도로"를 설계 수준에서 정리한다. **코드는 작성하지 않는다.**

### 한 줄 결론

> **가능하다.** 단, 현재 macOS/Windows 데스크톱 전용 + polling + 로컬 알림 구조 위에 얹는 "작은 기능"이 아니라, **새 iOS+watchOS 앱 + 진짜 APNs 푸시 백엔드를 세우는 새 플랫폼 라인**이다. STT 답장은 watchOS 네이티브라 쉬운 편이고, 어려운 핵심은 ① 익명 세션 다기기 공유, ② private Storage 영상을 푸시에 싣기, ③ 푸시 발송 서버 경계 신설이다. **추가 비용은 0원**(개발자 계정 이미 지불, 나머지 무료 티어 내).

---

## 2. 확정된 결정 로그

| # | 결정 | 값 |
|---|---|---|
| D1 | 접근 범위 | 설계·타당성 문서 먼저 (본 문서) |
| D2 | 폰/워치 역할 | **받기 + STT 텍스트 답장만** (영상 촬영·전송 없음) |
| D3 | 신원 연속성 | **폰 = 데스크톱과 같은 나** (세션 핸드오프) |
| D4 | 푸시 백엔드 | **A안 = Vercel serverless + Supabase DB Webhook + APNs** |
| D5 | 영상 조회 수준 | **알림에 썸네일 + 탭하면 워치 앱에서 3초 재생** |
| D6 | 페어링 방식 | **데스크톱 QR → 폰 카메라 스캔 → 세션 임포트** |
| D7 | STT 답장 | **알림 인라인 받아쓰기 + 워치 앱 내 답장**, 목적지 `ping_send_chat` |
| D8 | 테스트/배포 | **TestFlight (production APNs 환경)** |
| D9 | 전제 | Apple Developer Program 가입 완료 ✓ |

---

## 3. 현재 아키텍처 요약 — 왜 작은 기능이 아닌가

| 항목 | 현재 상태 | 이 기능과의 관계 |
|---|---|---|
| 플랫폼 타깃 | `project.yml`에 `Ping`(macOS 13), `PingTests`만. **iOS/watchOS 0개** | 새 타깃 신설 필요 |
| 알림 | 로컬 알림(`Ping/Notifications/LocalNotificationCenter.swift`, `UNUserNotificationCenter`). 데스크톱 앱이 `ping_incoming_messages`를 2초 polling 후 배너 표시. **APNs 코드 0줄** | 진짜 원격 푸시(APNs) 신설 필요 |
| 인증 | 익명 인증만. 기기마다 별도 익명 uid. 세션은 `Accounts.json`(+레거시 `SupabaseSession.json`) 직렬화 | 폰이 "같은 나"가 되려면 세션 공유 메커니즘 필요 |
| 푸시 발송 서버 | 없음. Edge Functions 없음, 서버 예약 작업 없음(AGENTS.md §6 불변식) | 메시지 도착 시 APNs를 쏘는 컴포넌트 필요 |
| Realtime | `ChatRealtimeService`가 Realtime 시도 후 polling fallback. **앱이 떠 있어야 동작** | 워치는 앱이 꺼져 있으므로 Realtime/polling으로 불가 → 푸시 필수 |
| 채팅 전송 | `ping_send_chat` RPC 존재 | 답장 목적지로 재사용 |
| 웹 | Vercel(Vite) `web/`, `web/api/` **아직 없음** | 푸시 발송 함수 자리로 신설 |

**핵심 제약**: 워치는 평소 앱이 실행돼 있지 않다. 따라서 "데스크톱 앱이 polling하다 띄우는 로컬 알림" 모델은 워치에 **원천적으로 적용 불가**하고, 서버가 능동적으로 쏘는 APNs가 반드시 필요하다.

---

## 4. 전체 아키텍처

```
[파트너] 데스크톱/윈도우에서 ping 전송
   │  ping_create_message → public.messages INSERT (receiver uid별 row)
   ▼
┌─────────────────────────────────────────────┐
│ Supabase (무료 플랜, Edge Function 0개 유지)  │
│  • messages INSERT                            │
│  • Database Webhook ──────────────┐           │
│  • device_tokens 테이블           │           │
│  • ping_register/remove_device_token RPC      │
└───────────────────────────────────┼──────────┘
                                     │ HTTPS POST (+공유 시크릿)
                                     ▼
                      ┌───────────────────────────────┐
                      │ Vercel serverless              │
                      │  web/api/push.ts               │
                      │  • 시크릿 검증                  │
                      │  • receiver의 device_tokens 조회│
                      │  • 영상 short-lived signed URL  │
                      │  • APNs JWT(.p8) 서명 후 발송   │
                      └───────────────┬───────────────┘
                                      │ HTTP/2
                                      ▼
                                   [ APNs ]
                                      │
                          ┌───────────┴───────────┐
                          ▼                        ▼
                     [iPhone]  ──forward──▶  [Apple Watch]
                          │
   ┌──────────────────────┼───────────────────────────────┐
   │ Notification Service Extension(iOS):                   │
   │   signed URL로 3초 MP4 받아 알림에 첨부 → 썸네일 표시   │
   │ 사용자 동작:                                           │
   │   • 알림 탭 → 워치 앱에서 3초 재생 → ping_mark_message_seen
   │   • 알림 인라인 받아쓰기 답장 → ping_send_chat          │
   └────────────────────────────────────────────────────────┘
```

---

## 5. 새 구성요소 상세

### 5.1 공유 Swift Package (네트워크/모델 레이어 추출)

- 현재 `Ping/Backend/*`(SupabaseClient, MessageService, ChatMessageService, 모델 등)와 `Ping/Core/Models.swift`의 **순수 네트워크/모델 부분**을 SwiftPM 로컬 패키지(예: `PingKit`)로 추출.
- macOS 앱은 이 패키지를 소비하도록 바꾼다(동작 동일, import 경로만 변경). iOS·watch 타깃도 같은 패키지를 공유.
- 카메라/거울/AppKit 의존 코드는 패키지에 넣지 않는다(플랫폼 분리 유지).
- **원칙**: macOS 앱의 런타임 동작은 0 변경. 리팩터링은 "공유 가능한 부분만 위로 끌어올리기"로 한정(브레인스토밍의 isolation 원칙). 파일당 한 책임 유지(AGENTS.md §5).

### 5.2 iOS 동반 앱 (+ Notification Service Extension)

얇게 유지. 책임:

1. **페어링**: QR 스캐너로 데스크톱이 표시한 세션 핸드오프 페이로드를 읽어 임포트(§6).
2. **APNs 등록**: `registerForRemoteNotifications` → device token 수신 → `ping_register_device_token(token, platform:"ios", environment:"production")` 호출. 토큰 갱신/삭제 처리.
3. **Notification Service Extension**: `mutable-content:1` 푸시를 가로채 payload의 signed URL로 MP4 다운로드 → `UNNotificationAttachment`로 첨부(썸네일). 다운로드 실패 시 텍스트 알림으로 graceful fallback.
4. **알림 카테고리/액션**: `UNNotificationCategory`에 `UNTextInputNotificationAction`(답장) 등록 → 워치/폰 모두에서 인라인 받아쓰기 답장 노출.
5. **WatchConnectivity**: 임포트한 세션을 워치로 동기화(§5.3)해, 워치가 독립적으로 영상 fetch·답장 가능하게 함.
6. **UI**: 페어링 화면 + 상태 표시 정도. 메시지 목록/히스토리는 범위 밖(YAGNI).

### 5.3 watchOS 앱

- watchOS 독립 앱(폰 동반 설치). 책임:
  1. **재생**: 알림 탭 시 워치 앱 진입 → `ping_get_message`로 최신 메타 확인 → 세션 기반으로 영상 fetch(또는 NSE가 캐시한 파일 재사용) → 3초 재생.
  2. **답장**: 워치 앱 내 받아쓰기 입력 → `ping_send_chat(room, text)`.
  3. **seen**: 재생 완료 시 `ping_mark_message_seen(message_uuid)` 1회.
- 세션은 WatchConnectivity로 폰에서 받은 것을 watch Keychain/파일에 보관(데스크톱과 동일 익명 uid).
- 영상 조회 수준은 D5 확정: **알림 썸네일 + 탭 → 앱 재생**(인라인 자동재생은 범위 밖).

### 5.4 푸시 백엔드 — A안 (Vercel serverless + DB Webhook + APNs)

- **위치**: `web/api/push.ts` (Vercel Node serverless function 신설; 현재 `web/api/` 없음).
- **트리거**: Supabase Database Webhook — `public.messages` `INSERT` 시 `https://ping0min.vercel.app/api/push`로 POST. 헤더에 공유 시크릿.
- **함수 동작**:
  1. 공유 시크릿 검증(미일치 → 401).
  2. payload의 새 row에서 `receiver_uid`, 영상 path, `room_id`, sender nickname 추출.
  3. `device_tokens`에서 receiver의 활성 토큰 조회(service_role 키로 서버측 조회).
  4. 영상 객체의 **short-lived signed URL**(TTL 5~10분) 생성(`ping-videos` 비공개 버킷).
  5. APNs payload 구성: `aps.alert`(발신자/“ping 도착”), `aps.mutable-content:1`, `aps.category:"PING_MESSAGE"`, custom: `{messageId, roomId, videoSignedUrl, senderName}`. `apns-collapse-id = messageId`(재시도 중복 합치기).
  6. APNs HTTP/2로 발송. 인증은 **.p8 토큰 기반(JWT: keyId + teamId + .p8)**. `410 Unregistered` 응답 토큰은 `device_tokens`에서 정리.
- **APNs 환경**: TestFlight = **production**(`api.push.apple.com`). `device_tokens.environment`로 분기(개발 중 Xcode 직접 설치는 sandbox이므로 컬럼으로 구분).
- **비밀 보관**: `.p8` 키 내용, keyId, teamId, bundleId, webhook 공유 시크릿, Supabase service_role 키를 Vercel 환경변수로 보관(코드/깃 외부).
- **라이브러리**: HTTP/2 필요 → `apns2` 등 경량 라이브러리 또는 직접 http2 구현.

> A안 선택 이유: Supabase 안에 Edge Function을 0개로 유지("Edge Functions 없음" 불변식 보존)하고, 이미 운영 중인 Vercel에 함수 하나만 추가. 무료 플랜·익명 인증 모두 유지.

### 5.5 백엔드 스키마 변경 (새 마이그레이션 1개)

새 파일: `supabase/migrations/<timestamp>_device_tokens_and_push.sql`

- **테이블** `public.device_tokens`
  - `id uuid pk`, `uid uuid not null`(= auth.uid()), `token text not null`, `platform text`(`ios`/`watchos`), `environment text`(`production`/`sandbox`), `updated_at timestamptz`.
  - unique(`uid`,`token`).
  - **RLS**: 본인(`uid = auth.uid()`)만 select/insert/update/delete. 서버 발송 함수는 service_role로 RLS 우회.
- **RPC**(security definer):
  - `ping_register_device_token(token, platform, environment)` — upsert.
  - `ping_remove_device_token(token)` — 삭제(로그아웃/언레지스터 시).
- **Database Webhook**: `messages` AFTER INSERT → Vercel URL. (Supabase Dashboard 또는 `supabase_functions.http_request` 트리거로 선언; 마이그레이션에 포함 가능.)
- 적용: `npx supabase db push`(원격 링크/로그인 필요 시 사용자에게 요청 — AGENTS.md §2).

---

## 6. 신원 연속성 / 세션 핸드오프 (D3)

### 목표

폰/워치가 데스크톱과 **같은 익명 uid**로 동작 → "나에게 온 ping"이 모든 내 기기에 도달, 답장도 "나"로 표기.

### 메커니즘 (D6: QR)

1. macOS Settings에 "기기 추가" → 현재 익명 세션(access+refresh token, 이미 `Accounts.json` 구조로 직렬화 가능)을 담은 **QR 코드** 표시.
2. 폰이 카메라로 스캔 → 세션 임포트 → 폰이 같은 uid로 인증.
3. 폰 → 워치로 WatchConnectivity 세션 동기화.

### ⚠️ 핵심 리스크: refresh token rotation

Supabase GoTrue는 기본적으로 refresh token을 **갱신 때마다 회전(rotation)**한다. 같은 refresh token을 데스크톱·폰이 동시에 들고 있으면, 먼저 갱신한 기기가 나머지 토큰을 무효화 → 다른 기기 로그아웃. 게다가 본 앱은 세션 만료 시 새 익명 사용자로 자동 전환하지 않고 `supabaseSessionExpired`를 띄우는 불변식이라(AGENTS.md §8, 데이터 보호 목적), 그 기기는 그냥 끊긴다.

**권장 해소안 (구현 시 결정 §13-R1)**: Supabase Auth 설정에서 **refresh token 회전 비활성화 또는 reuse interval 확대**. 2인 규모 hobby 앱에서 수용 가능한 보안 트레이드오프이며 되돌릴 수 있다. 대안(단일-refresher 모델, 서버측 세션 발급)은 익명 사용자 특성상 깔끔하지 않아 비권장. → 본 트레이드오프를 §10에 보안 항목으로 명시.

---

## 7. 데이터 흐름 (end-to-end)

1. 파트너가 데스크톱/윈도우에서 ping 전송 → `ping_create_message`로 `messages`에 receiver별 row INSERT.
2. Supabase DB Webhook이 `INSERT` 감지 → Vercel `/api/push`로 POST(+시크릿).
3. Vercel 함수: 시크릿 검증 → receiver의 `device_tokens` 조회 → 영상 signed URL 생성 → APNs payload 구성 → HTTP/2 발송.
4. APNs → iPhone 전달 → (워치 착용·잠금 등 조건에 따라) Apple Watch로 forward.
5. iOS NSE가 signed URL로 MP4 다운로드 → 알림에 썸네일 첨부.
6. 사용자: 알림 탭 → 워치 앱에서 3초 재생 → `ping_mark_message_seen`. (재생 완료 시 seen은 기존 데스크톱과 동일 RPC로 동기화.)
7. 또는 알림 인라인 받아쓰기 답장 → `ping_send_chat(room, text)` → 룸 chat에 "나"로 게시.

데스크톱은 기존 polling/Realtime 그대로 → 데스크톱+폰 동시 보유 시 데스크톱 로컬 알림 + 폰 푸시 둘 다 표시(정상, 기기별). 기기 내 재시도 중복은 `apns-collapse-id`로 합침.

---

## 8. STT 답장 흐름 (D7)

- watchOS 네이티브 받아쓰기(dictation)/스크리블 → 텍스트.
- 경로 ①(앱 안 열고): 알림의 `UNTextInputNotificationAction` → 액션 핸들러가 `ping_send_chat` 호출. 핸들러를 처리하는 기기(폰 근처면 폰, 아니면 워치)가 유효 세션 필요 → §5.3대로 워치에도 세션 동기화해 독립 동작 보장.
- 경로 ②(앱에서): 워치 앱 재생 화면에서 받아쓰기 → `ping_send_chat`.
- 답장 목적지: 해당 룸 chat(기존 RPC 그대로). 별도 신규 테이블 불필요.

---

## 9. 불변식 충돌과 해소

| AGENTS.md 불변식 | 충돌 여부 | 해소 |
|---|---|---|
| Edge Functions 없음 | ❌ 안 깸 | 발송을 Supabase 밖 Vercel serverless로(§5.4). Supabase 내 함수 0개 유지 |
| 익명 인증만(이메일/소셜 금지) | ❌ 안 깸 | 폰은 세션 핸드오프로 같은 익명 uid. 신규 인증수단 0 |
| 무료 플랜 유지 | ❌ 안 깸 | DB Webhook·APNs 무료, Vercel 무료 티어(§11) |
| 서버 예약 작업 없음 | ⚠️ 의미 확장 | "예약 작업"은 여전히 없음. 단 **이벤트 기반 발송 함수 1개**가 새로 생김(예약이 아니라 webhook 트리거) |
| polling 유지 | ❌ 안 깸 | 데스크톱 polling/Realtime 그대로. 푸시는 워치/폰용 **추가** 경로 |
| 세션 만료 시 새 익명 사용자 자동 전환 금지 | ⚠️ 주의 | refresh rotation 비활성화로 다기기 만료 자체를 예방(§6, §10) |
| macOS 13+/Swift 6/.pingGlassEffect/SMAppService | ❌ 무관 | macOS 앱 코드 동작 불변, 패키지 추출만 |

**새로 도입되는 긴장점**(문서화 필수): (a) "서버 컴포넌트 0개" → Vercel 함수 1개, (b) refresh token 회전 비활성화의 보안 트레이드오프. 둘 다 의도적·문서화된 결정으로 남긴다.

---

## 10. 보안·프라이버시

- 영상은 비공개 `ping-videos` 버킷 유지. 푸시에는 **short-lived signed URL**만 실어 NSE가 받음(만료 5~10분).
- `.p8`·service_role·webhook 시크릿은 Vercel 환경변수에만. 깃/클라이언트 비포함.
- `device_tokens`는 RLS로 본인만 접근. 서버 발송만 service_role로 우회.
- DB Webhook은 공유 시크릿 헤더로 출처 검증.
- **트레이드오프(명시)**: refresh token 회전 비활성화 시 토큰 탈취 내성이 약간 낮아짐. 2인 규모에서 수용. 규모 확장 시 재검토 항목.
- 세션 핸드오프 QR은 유효 세션을 그대로 담으므로, **QR 노출 = 계정 접근**. QR은 짧게 표시하고(타임아웃) 화면 외 노출 주의 안내.

---

## 11. 비용·쿼터 분석

| 항목 | 비용 |
|---|---|
| Apple Developer Program | **이미 지불($99/년)** |
| APNs | 무료 |
| Supabase Database Webhook | 무료(플랜 내) |
| Vercel serverless 함수 | 무료 티어 내(2인 메시지량 기준 무시 가능) |
| Supabase Storage signed URL | 무료(기존 버킷) |
| **추가 비용 합계** | **0원** |

---

## 12. 난이도·작업량 추정 (phase outline, 구현 플랜은 별도)

전체 난이도: **중상(中上)** (폰 영상 send 제외 덕분). 단계 개요:

- **P1. 백엔드 토대**: `device_tokens` 마이그레이션 + RPC + DB Webhook. Vercel `/api/push` 함수(APNs .p8 발송) + 환경변수. — *난이도 중*
- **P2. 공유 패키지 추출**: `PingKit`로 네트워크/모델 분리, macOS 앱 무동작-변경 검증. — *난이도 중, 회귀 리스크 주의*
- **P3. iOS 앱 + APNs 등록 + NSE**: 토큰 등록, signed URL 영상 첨부, 알림 카테고리/답장 액션. — *난이도 상(NSE+private storage)*
- **P4. 세션 핸드오프**: macOS QR 표시 + iOS 스캔 임포트 + refresh rotation 설정. — *난이도 상(인증)*
- **P5. watchOS 앱**: 재생 + 받아쓰기 답장 + seen + WatchConnectivity 세션 동기화. — *난이도 중상*
- **P6. TestFlight 배포·2인 E2E**: production APNs로 파트너 기기까지 종단 검증. — *난이도 중*

가장 어려운 지점: P3(NSE로 비공개 영상 알림 첨부), P4(익명 다기기 세션). STT는 P5 안에서 비교적 쉬움.

---

## 13. 리스크와 미해결 결정 (구현 단계로 이연)

- **R1. refresh token 회전 처리**: 회전 비활성화 vs reuse interval 확대 — 구현 시 Supabase 설정으로 확정(§6 권장: 비활성화).
- **R2. 워치 알림 영상 첨부 표시 정도**: watchOS의 알림 미디어 첨부 렌더링은 기기/상황별 차이. D5대로 "썸네일+탭 재생"을 기준선으로, 실제 표시 수준은 P5에서 디바이스 검증.
- **R3. 답장 액션 핸들러 위치**: 폰 근처/원거리에 따라 폰 또는 워치가 핸들. 워치 세션 동기화로 양쪽 모두 `ping_send_chat` 가능하도록 보장(§8).
- **R4. NSE 다운로드 실패/대용량**: 50MB 제한이지만 3초 클립은 작음. 실패 시 텍스트 알림 fallback.
- **R5. 패키지 추출 회귀**: P2에서 macOS 기존 테스트(`xcodebuild ... test`) 그린 유지로 가드.
- **R6. APNs 환경 혼선**: TestFlight(production) vs Xcode 직접(sandbox). `device_tokens.environment`로 분기 필수.
- **R7. Windows 사용자**: 윈도우 클라이언트엔 워치/푸시 없음(애플 생태계 한정). 범위 밖 — 윈도우 발신 → 애플 수신은 동작(발송 경로는 공통 messages 테이블).

---

## 14. 명시적 범위 밖

- 폰/워치에서 **영상 촬영·전송**(D2).
- Windows 측 워치/푸시.
- Android.
- 그룹 룸 대규모 fan-out 최적화(현 8룸/4인 제한 내에선 단순 루프로 충분).
- iOS 앱의 풍부한 히스토리/룸 관리 UI(YAGNI; 데스크톱이 담당).

---

## 15. 다음 단계

1. **사용자 검토**(본 문서). 변경 요청 반영.
2. 승인되면 **writing-plans** 스킬로 P1~P6 구현 플랜(bite-sized task + 커밋 단위) 작성.
3. 구현은 별도 세션에서 executing-plans로 진행. P1(백엔드)부터 시작 권장.

---

- **문서 상태**: 설계·타당성 / 사용자 검토 대기
- **선행 전제 충족**: Apple Developer Program ✓
