# 채팅 + 반응 + 답장 — 디자인 명세 (Spec G)

- **작성일**: 2026-05-22
- **상태**: 브레인스토밍 완결, 구현 계획 작성 대기
- **버전**: v0.3 후보 (PING_PROJECT_SPECIFICATION.md v2.2 + v0.2 amendments 위에 누적)

## 0. 배경

v0.2까지의 Ping은 2초 영상이 유일한 표현 채널이다. 사용자 피드백:
- 히스토리에서 영상을 회상하다 보면 "이건 뭐였더라" 같은 짧은 답장/감상이 필요함.
- setlog가 영상 vlog에 부수 채팅을 결합한 패턴으로 retention에 성공.
- 그러나 채팅을 도입해도 Ping의 시그니처 — spatial overlay, 즉시성, raw 2초 영상 — 는 흔들리면 안 됨.

이번 spec은 **영상 보조 채널로서의 채팅 + 반응 + 답장**을 도입한다.

## 0.1 핵심 결정 (브레인스토밍 결과)

| 차원 | 결정 | 근거 |
|---|---|---|
| 위상 | 영상 보조·회상 — spatial overlay 없음, 히스토리 안에서만 read/write | Ping spatial 정체성 보존 |
| 컨텐츠 | 텍스트만 (이모지 inline 포함) | 보조 채널 단순성, v0.4+에서 첨부 고려 |
| 반응 UI | Quick set 6개 + 더보기 picker (iMessage hybrid) | 결정 빠름 + 유연성 |
| 동기화 | Supabase Realtime (Phoenix WebSocket) | 채팅 immediacy 요구 |
| 알림 | 정식 macOS 푸시 (영상과 동일) | 사용자가 video 채널과 동등 알림 선호 |
| 답장 | iMessage 스타일 reply (quote 표시) | 영상에 대한 텍스트 답장이 자연스럽게 표현 가능 |

---

## G1. 데이터 모델 + 마이그레이션

### G1.1 새 테이블

```sql
-- 채팅 메시지
create table public.chat_messages (
    id uuid primary key default gen_random_uuid(),
    room_id uuid not null references public.rooms(id) on delete cascade,
    sender_uid uuid not null references public.profiles(id) on delete cascade,
    sender_nickname text not null,
    body text not null check (char_length(body) > 0 and char_length(body) <= 2000),
    reply_to_chat_id uuid references public.chat_messages(id) on delete set null,
    reply_to_video_id uuid references public.messages(id) on delete set null,
    created_at timestamptz not null default now(),
    constraint chat_reply_target_xor check (
        reply_to_chat_id is null or reply_to_video_id is null
    )
);

create index chat_messages_room_created_at_idx
    on public.chat_messages (room_id, created_at desc);

-- 반응 (영상 + 텍스트 둘 다 target)
create table public.message_reactions (
    id uuid primary key default gen_random_uuid(),
    chat_message_id uuid references public.chat_messages(id) on delete cascade,
    video_message_id uuid references public.messages(id) on delete cascade,
    uid uuid not null references public.profiles(id) on delete cascade,
    emoji text not null check (char_length(emoji) <= 16),
    created_at timestamptz not null default now(),
    constraint reaction_target_xor check (
        (chat_message_id is null) <> (video_message_id is null)
    ),
    unique (chat_message_id, uid, emoji),
    unique (video_message_id, uid, emoji)
);

create index reactions_chat_idx on public.message_reactions (chat_message_id) where chat_message_id is not null;
create index reactions_video_idx on public.message_reactions (video_message_id) where video_message_id is not null;
```

**한 메시지당 사용자 반응**: Slack 패턴 — 한 사용자가 한 메시지에 여러 emoji 반응 가능 (✓ 동시 ❤️ + 👍 OK), 같은 emoji는 중복 불가.

### G1.2 profiles 확장

```sql
alter table public.profiles
    add column if not exists last_read_chat_at jsonb not null default '{}'::jsonb;
-- 형태: { "room-uuid-1": "2026-05-22T10:00:00Z", ... }
```

### G1.3 RLS

| 테이블 | insert | select | delete |
|---|---|---|---|
| chat_messages | 룸 멤버만, sender_uid = auth.uid() | 룸 멤버만 | sender만 |
| message_reactions | 룸 멤버만, uid = auth.uid() | 룸 멤버만 | uid = auth.uid()만 |

### G1.4 새 RPC

- `ping_send_chat(room_uuid, body_text, reply_chat_uuid, reply_video_uuid) → uuid`
  - 룸 멤버 검증, body 길이 검증, reply target XOR 검증
  - reply target이 같은 룸인지 확인 (cross-room reply 차단)
- `ping_react(target_kind text, target_uuid uuid, emoji_text text) → boolean`
  - target_kind ∈ ('chat', 'video')
  - 이미 본인이 같은 emoji 반응 있으면 toggle off (delete) + return false
  - 없으면 insert + return true
- `ping_room_chat_messages(room_uuid, before_ts, page_limit default 50) → setof chat_messages`
  - 룸 멤버 검증
- `ping_message_reactions(chat_ids uuid[], video_ids uuid[]) → table(target_kind text, target_id uuid, emoji text, total_count int, my_reacted boolean)`
  - 룸 멤버 검증 후 집계 반환
- `ping_mark_room_read(room_uuid)` → update profiles.last_read_chat_at[room_uuid] = now()
- `ping_unread_chat_counts() → table(room_id uuid, unread_count int)`
  - 룸별로 last_read 이후 sender_uid != me인 메시지 수

### G1.5 Cleanup

기존 `ping_cleanup_expired_data()`에 chat_messages + message_reactions 30일 cleanup 추가 (영상 메시지 정책 일치).

---

## G2. Realtime 인프라

### G2.1 의존성

`supabase-swift` Swift Package의 `Realtime` 모듈 추가. 검증된 구현, Phoenix protocol heartbeat/재연결 내장.

### G2.2 ChatRealtimeService

```swift
@MainActor
final class ChatRealtimeService: ObservableObject {
    @Published private(set) var lastEvent: ChatRealtimeEvent?
    @Published private(set) var connectionState: ConnectionState
    
    enum ConnectionState { case disconnected, connecting, connected }
    enum ChatRealtimeEvent {
        case chatInserted(ChatMessage)
        case chatDeleted(messageId: String, roomId: String)
        case reactionChanged(target: ReactionTarget, emoji: String, total: Int)
    }
    
    func subscribe(roomIds: [String]) async
    func unsubscribeAll() async
}
```

- 사용자가 가입한 모든 룸의 채널을 subscribe.
- `room:<uuid>:chat` 채널 (Postgres CDC on chat_messages + message_reactions filtered by room_id).
- 연결 끊김 시: exponential backoff (1s, 2s, 5s, 10s, 20s cap). 그동안 폴링 fallback (10s 간격으로 `ping_room_chat_messages`).

### G2.3 통합 지점

- `AppDelegate`가 bootstrap 후 `ChatRealtimeService.subscribe(roomIds: appState.rooms.map(\.id))` 호출.
- `roomObserverTask`가 룸 list 변경을 감지하면 `subscribe`를 다시 호출 (재구독).
- 알림 처리 흐름은 §G4.

---

## G3. UI 변경

### G3.1 HistoryViewModel — 통합 타임라인

```swift
enum TimelineItem: Identifiable, Hashable {
    case video(VideoMessage)
    case chat(ChatMessage)
    
    var id: String { ... }
    var createdAt: Date? { ... }
    var senderUid: String { ... }
}
```

`HistoryViewModel`:
- `loadedVideos: [VideoMessage]`, `loadedChats: [ChatMessage]` 별도 로드
- `groups: [DayGroup<TimelineItem>]` — 시간 역순 머지 후 일별 그룹
- `selectRoom`에서 두 fetch 병렬 (`async let`)
- Realtime이벤트 수신 시 해당 list에 insert + groups 재계산

### G3.2 ChatMessageRowView

iMessage 스타일 bubble.

| 요소 | 디자인 |
|---|---|
| 정렬 | sender == me면 우측, 아니면 좌측 (기존 video row와 일관) |
| Bubble | 받은 건 회색 (`Color.gray.opacity(0.15)`), 보낸 건 accent (`Color.accentColor`) |
| Reply quote | bubble 위 작은 줄임 텍스트 (sender name + 첫 60자) 또는 영상 썸네일 (40×40) |
| 발신자 닉네임 | 룸 멤버 3명+ 일 때만 bubble 위 caption |
| Body | 멀티라인, max width 360, padding 10 horizontal/8 vertical |
| Reactions strip | bubble 하단 작은 chip들 — `❤️ 2` 형태 |
| 시각 | bubble 옆 우측/좌측 small caption (호버 시에만 표시) |
| 호버 액션 | 우측 (sender) 또는 좌측 (received)에 3개 버튼: reply ⤴️ / react 🙂 / delete 🗑(sender만) |

### G3.3 메시지 입력 영역

타임라인 하단 sticky 영역.

```
┌──────────────────────────────────────┐
│ ↩︎ [Reply preview]              [×]  │  ← reply 상태일 때만
├──────────────────────────────────────┤
│ [TextField ─ 멀티라인]       [전송]   │
└──────────────────────────────────────┘
```

- TextField: 최대 6줄까지 자동 확장, 그 이상 스크롤
- 일반 Enter = 줄바꿈, **Cmd+Enter = 전송**
- 입력 비어 있으면 전송 비활성화
- 2000자 제한
- 발송 후 입력 초기화 + reply 해제

### G3.4 반응 picker

메시지 호버 → 🙂 클릭 → 작은 popover:

```
┌────────────────────────────┐
│ ❤️ 👍 👎 😂 ‼️ ❓  ＋        │
└────────────────────────────┘
```

- Quick set 6개 + `＋` 버튼
- `＋` → `NSApp.orderFrontCharacterPalette(nil)` 시스템 이모지 panel
- 본인이 이미 단 emoji는 highlight, 다시 클릭하면 toggle off

### G3.5 반응 칩 (메시지 bubble 하단)

- bubble 외부 바로 아래에 작은 capsule. `emoji count` 형태. 1개면 count 생략.
- 본인이 단 emoji는 accent border.
- 칩 클릭 = toggle (자기 반응 추가/제거).
- 호버 시 풀 정보 tooltip ("alice, bob 외 3명").

---

## G4. 알림 흐름

새 chat_message Realtime 이벤트 도착 시:

1. **Self filter**: `sender_uid == currentUser.id` 면 skip.
2. **Dedup**: `notifiedChatMessageIds: Set<String>` UserDefaults (영상과 동일 패턴, 최대 500개 cap).
3. **Suppress when window open + room active**: 히스토리 윈도우가 떠 있고 그 룸이 현재 선택 중이면 알림 skip + 자동 scroll로 새 메시지 노출.
4. macOS UserNotification 표시:
   - title: `"{sender_nickname} · {room_name}"`
   - body: `body` truncate 200자
   - action: 'View' → `LocalNotificationCenter.onViewChatMessage(messageId, roomId)`
5. 알림 클릭 → 콜백:
   - 히스토리 윈도우 열고
   - 사이드바에서 해당 룸 선택
   - 메시지 list에서 해당 ID로 scroll
   - `expandedMessageId` 설정 (video인 경우 인라인 재생, chat은 highlight)

기존 `LocalNotificationCenter.onViewMessage`(영상용)와 분리된 새 callback `onViewChatMessage` 추가.

---

## G5. 메시지 보관 정책

| 데이터 | 보관 |
|---|---|
| chat_messages | 30일 (영상과 동일) |
| message_reactions | 30일 (또는 대상 메시지 삭제 시 cascade) |
| profiles.last_read_chat_at | 영구 (작은 jsonb) |

`ping_cleanup_expired_data()` 확장.

---

## G6. 메시지 액션

### G6.1 삭제
- **Sender만** 자기 chat_message 삭제 가능 (`ping_delete_chat(chat_uuid)`).
- 영상 메시지 삭제 정책은 기존 그대로 (sender = 완전 삭제 / receiver = hidden_for_receiver).

### G6.2 편집
**없음**. iMessage처럼 raw 메시지 유지. v0.4+ 후보.

### G6.3 reply
- chat row의 `↩︎ reply` 호버 액션 → 입력 영역에 reply 미리보기 표시.
- video row에서도 같은 reply 액션 가능 (video에 대한 텍스트 답장).
- reply target이 cleanup으로 삭제되면 quote에 "삭제된 메시지" placeholder.

---

## G7. 에러 처리

| 상황 | 처리 |
|---|---|
| Realtime 연결 실패 | 자동 재연결 + 10s polling fallback. 연결 상태 표시는 윈도우 헤더에 작은 dot (회색 disconnected, 노란 connecting, 녹색 connected). |
| 채팅 전송 실패 (네트워크) | 입력 영역 위에 빨간 retry pill "전송 실패 — 다시 시도". 클라이언트 queue에 보관, 재연결 시 자동 재전송 시도. |
| 반응 RPC 실패 | UI optimistic update → 실패 시 revert + 작은 toast. |
| 답장 대상 메시지 삭제됨 | quote에 "삭제된 메시지" placeholder. |
| 알림 권한 거부 | 영상과 동일, 사용자가 시스템 설정에서 허용해야. 채팅 알림만 따로 권한 안 받음. |

---

## G8. 호환성

- v0.2 이하 클라이언트: chat_messages 테이블 사용 안 함. Realtime 연결도 시도 안 함. 영상 흐름 그대로.
- v0.3 이상: chat 인프라 사용. v0.2 이하 메시지와 섞여 timeline 표시 가능 (영상만 보임).
- 마이그레이션은 backward-compatible (새 테이블/컬럼만 추가).

---

## G9. 테스트 전략

| 영역 | 방식 |
|---|---|
| `ChatMessage` Codable | 단위 — reply field nullable, 누락 시 nil |
| `HistoryViewModel.mergeTimeline` | 단위 — 영상 + 채팅 시간순 인터리브, 같은 시각 tie-break |
| `MessageReaction` toggle 로직 | 단위 — RPC stub으로 |
| Realtime 연결 | mock channel — 통합 테스트. 실제 ws 연결은 수동 smoke. |
| 알림 dedup + suppress | 단위 — yieldedIds + windowOpen + roomActive 조합 |
| 입력 필드 multiline + Cmd+Enter | SwiftUI snapshot 또는 수동 smoke |

---

## G10. 클라이언트 이벤트 트래킹

v0.2에서 추가한 `client_events` 인프라 활용. 신규 이벤트:

- `chat_sent` (room_id, body_length, is_reply: bool, reply_kind: 'chat' | 'video' | 'none')
- `chat_received_view` (room_id)
- `reaction_added` (target_kind, emoji)
- `reaction_removed` (target_kind, emoji)
- `chat_notification_clicked`
- `realtime_disconnected` (reason: timeout | error | manual)
- `realtime_reconnected` (after_seconds)

---

## G11. 비스코프 (이번 spec 외)

명시적으로 v0.3 G에서 안 함:
- 메시지 편집 → v0.4+
- 이미지/스티커 첨부 → v0.4+
- 영상 답장에 영상으로 답장 (영상 → 영상 reply) → v0.4+. 현재는 텍스트만 가능.
- 스레드(Slack 패턴) → 단일 피드 유지
- 메시지 검색 → v0.4+
- Realtime을 영상 메시지에도 적용 (현재 polling 유지) → 별도 spec
- 그룹 멘션 (@닉네임) → v0.4+

---

## G12. 핵심 결정 요약

- **영상 보조 채널**로 챗 도입. spatial overlay는 영상만 유지.
- **텍스트 + 반응 + reply** 세 가지 액션. 그 외는 v0.4+ 보류.
- **Supabase Realtime**으로 실시간 동기화. supabase-swift Realtime 모듈 의존.
- **iMessage UX 차용** — bubble + reply quote + Tapback-like 반응.
- **알림은 영상과 동일 수준** — 사용자가 채팅도 신경 쓰는 채널로 인식.
- **30일 보관**으로 영상 정책 일관.
