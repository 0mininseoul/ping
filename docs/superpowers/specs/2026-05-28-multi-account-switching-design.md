# 다중 계정 전환 (macOS, 오너 전용) — 설계

- 날짜: 2026-05-28
- 상태: 설계 승인 대기 → 구현 계획
- 범위: macOS Ping 앱에 한정. 다른 사용자에게 배포되는 일반 기능이 아니라 오너(영민) 전용으로 숨겨진 기능.

## 1. 개요

Ping은 현재 한 기기에서 **하나의 익명 Supabase 계정**만 사용한다. 이 설계는 한 기기에서 **여러 익명 계정을 보관하고 앱 안에서 손쉽게 전환**하는 기능을 추가한다. 비활성 계정은 백그라운드에서 듣지 않으며, 그 계정으로 **전환할 때 그동안 밀린 모든 알림(영상 핑 / 초대 / 채팅)을 모아서** 보여준다.

이 기능은 활성 계정의 닉네임이 `영민`일 때만 노출된다.

### 목표
- 한 기기에 여러 익명 계정을 비파괴적으로 보관.
- 앱 내에서 계정 추가 / 전환 / (명시적) 삭제.
- 전환 시 해당 계정의 밀린 알림(영상·초대·채팅) 캐치업.
- 닉네임 `영민` 게이트로 일반 사용자에게는 숨김.

### 비목표
- 비활성 계정의 백그라운드 실시간 수신 (한 번에 한 세션만 라이브).
- 다른 기기에서 같은 익명 계정으로 로그인 (익명 계정은 자격증명이 없어 복구·이전 불가).
- 관리자 권한 개념 (두 번째 계정은 권한이 동등한 별개의 익명 계정).
- iOS/Windows 클라이언트 변경.

## 2. 현재 구조 (관련 부분)

- `Ping/Backend/SupabaseClient.swift`
  - `SupabaseClient.shared` 싱글턴이 **단일** `session: SupabaseSession`(`accessToken`, `refreshToken`, `expiresAt`, `userId`)을 보유.
  - `private enum SupabaseSessionStore`가 `Application Support/Ping/SupabaseSession.json` + `UserDefaults("ping.supabase.session")`에 단일 세션을 저장.
  - `bootstrap()` → 저장 세션 로드 또는 익명 가입(`signInAnonymously` = 항상 새 익명 유저 생성). `currentUid` 발행.
- `Ping/AppDelegate.swift`
  - `bootstrapBackend()` → uid 확보, 프로필 조회, `appState.currentUser` 설정, `startObservers(uid:)`.
  - `startObservers(uid:)` → 옵저버 3개: 룸(`roomObserverTask`, chatRealtime 구독 포함), 초대(`invitationObserverTask`), 영상 메시지(`incomingMessageTask`).
  - 영상 알림: `messageService.observeIncoming(uid:)`가 `ping_incoming_messages`를 2초 폴링하며 미수신 메시지를 yield. `shouldNotify`가 `notifiedMessageIds`(UserDefaults `ping.notifications.notifiedMessageIds`, 전역 키, 300개 캡)와 만료로 dedup. 오프라인 캐치업 경로 존재.
  - 채팅 알림: `chatRealtime.$lastEvent` → `handleChatRealtimeEvent`. **실시간 insert 시에만** 발생. 인메모리 `notifiedChatMessageIds`로 dedup. 밀린 채팅 캐치업 없음.
  - 초대 알림: `invitationService.observeIncoming(uid:)`가 대기 초대를 yield, `previousIds` 비교로 새 항목만 알림.
- `Ping/Core/AppState.swift`: `currentUser`, `rooms`, `pendingInvitations`, `resetTransientState()`.
- `Ping/Backend/ChatMessageService.swift`: `unreadChatCounts()` → `ping_unread_chat_counts`(룸별 미독 수), `markRoomRead`, `roomChatMessages(roomId:limit:)` → `ping_room_chat_messages`. **서버 권위 미독 개념 존재.**

## 3. 아키텍처 개요 (선택한 접근)

**다중 계정 저장소 + 활성 세션 교체 + 옵저버 재시작.**

- 한 번에 하나의 세션만 라이브 (선택한 "전환 시 캐치업"과 일치).
- 기존 `bootstrap → startObservers` 머신을 재사용. 전환 = 옵저버 정리 → 새 uid로 재-bootstrap → 밀린 알림이 자연 유입.

기각한 대안: 비활성 계정까지 듣는 N개의 라이브 세션 — 다중 소켓/세션 동시 유지로 무겁고, 백그라운드 수신은 비목표.

## 4. 컴포넌트 상세

### 4.1 `AccountStore` + `StoredAccount`

`SupabaseClient.swift` 내 `private enum SupabaseSessionStore`를 다중 계정 저장소로 교체/확장.

```
struct StoredAccount: Codable, Identifiable {
    let userId: String          // id
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var nickname: String         // UI 표시용 캐시. bootstrap 후 갱신.
    let addedAt: Date
}

struct AccountsFile: Codable {
    var accounts: [StoredAccount]
    var activeUserId: String?
}
```

- 저장 위치: `Application Support/Ping/Accounts.json` (단일 세션 파일과 같은 디렉터리).
- **마이그레이션**: `Accounts.json`이 없고 기존 `SupabaseSession.json`(또는 레거시 UserDefaults)이 있으면, 그 세션을 `accounts[0]`로 이전하고 `activeUserId`로 설정. `nickname`은 우선 빈 값/임시값으로 두고 bootstrap 후 프로필에서 채움.
- **레거시 미러**: 활성 계정의 세션을 기존 `SupabaseSession.json` + `UserDefaults("ping.supabase.session")`에도 계속 기록. 구버전으로 다운그레이드해도 활성 계정으로 동작하게 함.
- **토큰 갱신 반영**: `refreshSession` 성공 시 해당 `userId`의 `StoredAccount`의 토큰/만료를 갱신 후 파일 저장.
- 동시성: 기존 `withRefreshLock`(flock) 유지. 한 번에 한 세션만 활성이므로 계정 간 갱신 경쟁 없음.

### 4.2 `SupabaseClient` 변경

- 발행 상태 추가:
  - `@Published private(set) var accounts: [StoredAccount]`
  - `@Published private(set) var activeUserId: String?` (기존 `currentUid`와 일치 유지)
- 메서드:
  - `func addAccount() async throws -> String` — `signInAnonymously()`로 새 익명 유저 생성 → `accounts`에 추가 → 활성으로 설정 → 새 uid 반환.
  - `func switchTo(userId: String) async throws` — `activeUserId` 변경, 내부 `session`을 해당 계정으로 교체(필요 시 refresh), `currentUid` 발행. 진행 중 `authSessionTask` 취소.
  - `func removeAccount(userId: String)` — 저장소에서 제거. (호출부에서 영구 손실 경고 후에만 호출.) 활성 계정 삭제 시 남은 계정 중 하나로 활성 전환 또는 계정 0개면 익명 신규 가입 경로로.
- 활성 세션 해석은 `activeUserId`에 매칭되는 `StoredAccount` 기준.

### 4.3 전환 오케스트레이션 (`AppDelegate`)

새 메서드 `reloadForActiveAccount()`:
1. 전송 중(미러 reviewing/uploading) 또는 전환 진행 중이면 차단(가드 플래그).
2. 옵저버 취소: `roomObserverTask`, `invitationObserverTask`, `incomingMessageTask`.
3. `await chatRealtime.unsubscribeAll()`.
4. 열린 창 정리: 미러 창 닫기(`closeMirrorWindow`), 재생 창/캐시(`playbackWindows`, `playbackCache`, `playbackPrefetchTasks`) 정리.
5. `AppState` 초기화: `currentUser = nil`, `rooms = []`, `pendingInvitations = []`, `resetTransientState()`, `pendingRoomFocusId`/`lastSelectedRoomId` 초기화.
6. 인메모리 dedup 초기화: `notifiedChatMessageIds = []`.
7. `bootstrapBackend()` 재호출 → 새 uid로 프로필/옵저버 재시작 → 캐치업 유입.

`addAccount()` 흐름: 새 계정은 빈 상태이므로, 생성 후 기존 `showOnboarding(uid:)`(닉네임 입력 + 룸 생성/참여/나중에)를 재사용. 완료 시 옵저버 시작.

### 4.4 밀린 알림 캐치업 (전환 시)

전환 직후 새 계정 옵저버가 시작되며 다음이 보장되어야 함.

- **영상 핑**: 기존 `observeIncoming` 폴링이 `ping_incoming_messages`의 미수신분을 yield → `shouldNotify` 통과분 알림. 
  - 변경: `notifiedMessageIds` dedup 키를 **계정별**로 분리 → `ping.notifications.notifiedMessageIds:<uid>`. 계정 간 교차 억제/캡 침식 방지.
- **초대**: 기존 옵저버가 대기 초대 yield. 신규 시작이므로 `previousIds`가 비어 대기분을 알림. 
  - 변경: 재알림 방지용 dedup을 **계정별** 영속 셋(`ping.notifications.notifiedInviteIds:<uid>`)으로 추가.
- **채팅 (신규 작업)**: 전환 직후 명시적 캐치업 단계 추가.
  - `ChatMessageService.unreadChatCounts()`로 룸별 미독 수 조회.
  - 미독 > 0인 룸마다 `roomChatMessages(roomId:limit:)`로 최신 미독 채팅을 가져와 묶음 로컬 알림 1건 게시(예: "○○ 룸 · 새 메시지 N개", 본문은 최신 메시지 미리보기).
  - dedup: **영상과 동일 방식** — 계정별 영속 채팅 ID 셋 `ping.notifications.notifiedChatIds:<uid>`에 알림에 포함된 채팅 ID를 기록하고, 이미 기록된 ID는 건너뜀. 사용자가 해당 룸을 열면 `markRoomRead`로 서버 미독이 0이 되어 다음 전환부터 자연 정리.
  - 활성 동안의 신규 채팅은 기존 `handleChatRealtimeEvent` 실시간 경로 유지.

### 4.5 `영민` 게이트 + UI

- 게이트: bootstrap 후 활성 계정의 `nickname`이 `영민`(트림 후 정확히 일치)이면 기기 로컬 플래그 `UserDefaults("ping.multiAccount.unlocked") = true` 설정. 한 번 켜지면 유지 → 비-`영민` 계정으로 전환해도 스위처가 사라져 갇히지 않음.
- UI 위치: `Ping/UI/Setup/SettingsScene.swift`의 **일반(General)** 탭 하단에 "계정" 섹션을 조건부(`unlocked`일 때만) 추가.
  - 계정 목록: 닉네임 + 활성 표시(체크). 탭하면 `switchTo` → `reloadForActiveAccount`.
  - "계정 추가" 버튼 → `addAccount` → 온보딩.
  - 각 계정의 "삭제" → **영구 손실 경고 다이얼로그**("이 익명 계정은 복구할 수 없습니다") 확인 후에만 `removeAccount`.
- 보안: 목록은 **이 기기 `Accounts.json`에 저장된 계정만** 반영. 타인이 닉네임 `영민`을 입력해도 자신의 로컬(비어있는) 스위처만 열릴 뿐, 오너의 세션/자격증명은 절대 노출되지 않음(세션은 기기 로컬 저장).

## 5. 데이터 흐름 — 전환 시퀀스

```
사용자: 설정 → 계정 → [계정 B] 탭
  → SupabaseClient.switchTo(B)         // activeUserId=B, 세션 교체(+필요시 refresh)
  → AppDelegate.reloadForActiveAccount()
       옵저버/리얼타임/창/AppState/인메모리 dedup 정리
  → bootstrapBackend()                 // B의 프로필 로드, startObservers(B)
       영상: observeIncoming → 미수신분 알림 (per-account dedup)
       초대: observeIncoming → 대기분 알림 (per-account dedup)
       채팅: unreadChatCounts → 룸별 묶음 알림 (per-account dedup)
```

## 6. 엣지 케이스 & 에러 처리

- **전송 중 전환**: 미러가 reviewing/uploading이면 전환 차단(토스트/비활성). 가드 플래그로 중복 전환 방지.
- **토큰 만료(비활성 동안)**: 전환 시 저장된 `refreshToken`으로 갱신. Supabase refresh 토큰은 장수명. 갱신 실패 시 에러 표시하되 **계정을 자동 삭제하지 않음**(사용자가 명시적으로만 삭제).
- **활성 계정 삭제**: 남은 계정으로 자동 전환, 0개면 신규 익명 가입(기존 bootstrap 경로).
- **마이그레이션 안전**: `Accounts.json` 파싱 실패 시 레거시 단일 세션 경로로 폴백. 활성 세션은 항상 레거시 파일에도 미러되어 다운그레이드 호환.
- **온보딩 관련 전역 플래그**: `roomSetupDeferred` 등은 현재 전역. 다중 계정에서 혼동 시 계정별 키로 분리(필요 최소 범위에서).
- **닉네임 변경**: 활성 계정 닉네임을 `영민`으로 바꾸면 그 시점에 unlock. 이미 unlock된 기기는 유지.

## 7. 테스트 계획

- 단위:
  - `AccountStore`: 추가/전환/삭제/활성 선택, `Accounts.json` 직렬화, 레거시 `SupabaseSession.json` 마이그레이션, 레거시 미러 기록.
  - per-account dedup 키 생성/격리.
- 통합/수동:
  - 계정 추가 → 온보딩 → 룸 로딩 확인.
  - A→B 전환 시 A의 옵저버/리얼타임 정리, B의 룸·초대 재로딩.
  - B 비활성 동안 도착한 (영상/초대/채팅) → B로 전환 시 모두 알림으로 표시, 재전환 시 중복 알림 없음.
  - 게이트: 닉네임 ≠ `영민`이면 섹션 숨김. 한 번 `영민`이면 이후 유지.
  - 보안: 다른 닉네임 계정에선 타 계정 목록이 보이지 않음(빈 스위처).

## 8. 영향받는 파일 (예상)

- `Ping/Backend/SupabaseClient.swift` — `AccountStore`/`StoredAccount`, 다중 계정 API, 토큰 갱신 반영, 레거시 미러/마이그레이션.
- `Ping/AppDelegate.swift` — `reloadForActiveAccount()`, 전환 가드, per-account dedup 키, 채팅 캐치업 트리거.
- `Ping/Backend/ChatMessageService.swift` — (재사용) `unreadChatCounts`, `roomChatMessages`.
- `Ping/Notifications/LocalNotificationCenter.swift` — 채팅 묶음 캐치업 알림 헬퍼(필요 시).
- `Ping/UI/Setup/SettingsScene.swift` — 일반 탭 "계정" 섹션(조건부), 전환/추가/삭제 UI.
- `Ping/Core/AppState.swift` — (재사용) 초기화 헬퍼. 필요 시 보조 상태.
- 테스트: `PingTests/` 내 `AccountStore`/마이그레이션 테스트 신규.
```
