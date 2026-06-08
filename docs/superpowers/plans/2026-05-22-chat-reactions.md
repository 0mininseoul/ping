# Spec G — Chat + Reactions + Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec G (`docs/superpowers/specs/2026-05-22-chat-reactions-design.md`)를 구현해 v0.3을 출시한다. 영상 보조 채널로서 텍스트 채팅 + Tapback-스타일 반응 + iMessage reply.

**Architecture:** Phase 단위로 분리하되 의존성 순서로 진행:
1. DB 마이그레이션 (Phase A) → 2. Swift 모델 (Phase B) → 3. Services + RPC clients (Phase C) → 4. Realtime 인프라 (Phase D) → 5. HistoryViewModel 통합 타임라인 (Phase E) → 6. UI 컴포넌트 (Phase F) → 7. 알림 (Phase G) → 8. 분석 이벤트 + 회귀 + Release (Phase H).

**Tech Stack:** Swift 6 + SwiftUI/AppKit, Supabase Postgres + Realtime (WebSocket), `supabase-swift` Realtime 모듈, KeyboardShortcuts, XCTest.

**Phase 순서:**
1. **Phase A** — 마이그레이션 (chat_messages, message_reactions, profiles 확장, RPC 6개)
2. **Phase B** — Swift 모델 (ChatMessage, MessageReaction, TimelineItem, ReactionAggregate)
3. **Phase C** — Service 계층 (ChatMessageService, ReactionService, RoomReadService)
4. **Phase D** — Realtime (supabase-swift SPM 의존성 추가 + ChatRealtimeService + polling fallback)
5. **Phase E** — HistoryViewModel 통합 타임라인 (영상+채팅 머지, 그룹핑, Realtime 이벤트 처리)
6. **Phase F** — UI 컴포넌트 (ChatMessageRowView, ChatComposerView, ReactionPicker, ReactionChips, reply quote)
7. **Phase G** — 알림 (chat push notification + suppress + click → 자동 scroll)
8. **Phase H** — client_events 트래킹 + 회귀 + release 0.3.0

각 Phase 끝에서 `xcodebuild test` 통과 후 다음 진행.

---

## Phase A — Supabase 마이그레이션

### Task A1: chat_messages + message_reactions + profiles.last_read_chat_at + RPC 6개

**Files:**
- Create: `supabase/migrations/20260522000100_chat_and_reactions.sql`

- [ ] **Step 1: Write migration**

Create `supabase/migrations/20260522000100_chat_and_reactions.sql`:

```sql
-- Spec G: chat + reactions + reply

-- 1. profiles 확장 (read marker)
alter table public.profiles
    add column if not exists last_read_chat_at jsonb not null default '{}'::jsonb;

-- 2. chat_messages
create table if not exists public.chat_messages (
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

create index if not exists chat_messages_room_created_at_idx
    on public.chat_messages (room_id, created_at desc);
create index if not exists chat_messages_sender_idx
    on public.chat_messages (sender_uid, created_at desc);

alter table public.chat_messages enable row level security;

create policy chat_messages_select_member
    on public.chat_messages for select to authenticated
    using (
        exists (
            select 1 from public.room_members
            where room_id = chat_messages.room_id and user_id = auth.uid()
        )
    );

create policy chat_messages_insert_member
    on public.chat_messages for insert to authenticated
    with check (
        sender_uid = auth.uid()
        and exists (
            select 1 from public.room_members
            where room_id = chat_messages.room_id and user_id = auth.uid()
        )
    );

create policy chat_messages_delete_sender
    on public.chat_messages for delete to authenticated
    using (sender_uid = auth.uid());

-- 3. message_reactions
create table if not exists public.message_reactions (
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

create index if not exists reactions_chat_idx on public.message_reactions (chat_message_id) where chat_message_id is not null;
create index if not exists reactions_video_idx on public.message_reactions (video_message_id) where video_message_id is not null;

alter table public.message_reactions enable row level security;

create policy reactions_select_member
    on public.message_reactions for select to authenticated
    using (
        case
            when chat_message_id is not null then exists (
                select 1 from public.chat_messages cm
                join public.room_members rm on rm.room_id = cm.room_id
                where cm.id = chat_message_id and rm.user_id = auth.uid()
            )
            when video_message_id is not null then exists (
                select 1 from public.messages m
                join public.room_members rm on rm.room_id = m.room_id
                where m.id = video_message_id and rm.user_id = auth.uid()
            )
            else false
        end
    );

create policy reactions_insert_own
    on public.message_reactions for insert to authenticated
    with check (uid = auth.uid());

create policy reactions_delete_own
    on public.message_reactions for delete to authenticated
    using (uid = auth.uid());

-- 4. RPC: send chat
create or replace function public.ping_send_chat(
    room_uuid uuid,
    body_text text,
    reply_chat_uuid uuid default null,
    reply_video_uuid uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    nickname text;
    new_id uuid;
begin
    if me is null then raise exception 'auth required'; end if;

    if reply_chat_uuid is not null and reply_video_uuid is not null then
        raise exception 'reply target must be exactly one';
    end if;

    if char_length(body_text) = 0 or char_length(body_text) > 2000 then
        raise exception 'invalid body length';
    end if;

    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    if reply_chat_uuid is not null and not exists (
        select 1 from public.chat_messages where id = reply_chat_uuid and room_id = room_uuid
    ) then
        raise exception 'reply chat not in this room';
    end if;

    if reply_video_uuid is not null and not exists (
        select 1 from public.messages where id = reply_video_uuid and room_id = room_uuid
    ) then
        raise exception 'reply video not in this room';
    end if;

    select profiles.nickname into nickname from public.profiles where id = me;
    if nickname is null then nickname := 'unknown'; end if;

    insert into public.chat_messages(room_id, sender_uid, sender_nickname, body, reply_to_chat_id, reply_to_video_id)
    values (room_uuid, me, nickname, body_text, reply_chat_uuid, reply_video_uuid)
    returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_send_chat(uuid, text, uuid, uuid) to authenticated;

-- 5. RPC: toggle reaction
create or replace function public.ping_react(
    target_kind text,
    target_uuid uuid,
    emoji_text text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    is_member boolean;
    existing_id uuid;
begin
    if me is null then raise exception 'auth required'; end if;
    if target_kind not in ('chat', 'video') then
        raise exception 'invalid target_kind';
    end if;
    if char_length(emoji_text) = 0 or char_length(emoji_text) > 16 then
        raise exception 'invalid emoji';
    end if;

    if target_kind = 'chat' then
        select exists (
            select 1 from public.chat_messages cm
            join public.room_members rm on rm.room_id = cm.room_id
            where cm.id = target_uuid and rm.user_id = me
        ) into is_member;
    else
        select exists (
            select 1 from public.messages m
            join public.room_members rm on rm.room_id = m.room_id
            where m.id = target_uuid and rm.user_id = me
        ) into is_member;
    end if;

    if not is_member then
        raise exception 'not a member of the target room';
    end if;

    if target_kind = 'chat' then
        select id into existing_id from public.message_reactions
        where chat_message_id = target_uuid and uid = me and emoji = emoji_text;
    else
        select id into existing_id from public.message_reactions
        where video_message_id = target_uuid and uid = me and emoji = emoji_text;
    end if;

    if existing_id is not null then
        delete from public.message_reactions where id = existing_id;
        return false;
    end if;

    if target_kind = 'chat' then
        insert into public.message_reactions(chat_message_id, uid, emoji)
        values (target_uuid, me, emoji_text);
    else
        insert into public.message_reactions(video_message_id, uid, emoji)
        values (target_uuid, me, emoji_text);
    end if;
    return true;
end;
$$;

grant execute on function public.ping_react(text, uuid, text) to authenticated;

-- 6. RPC: room chat messages (pagination)
create or replace function public.ping_room_chat_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns setof public.chat_messages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select * from public.chat_messages
    where room_id = room_uuid
      and (before_ts is null or created_at < before_ts)
    order by created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_chat_messages(uuid, timestamptz, int) to authenticated;

-- 7. RPC: message reactions aggregated
create or replace function public.ping_message_reactions(
    chat_ids uuid[],
    video_ids uuid[]
) returns table (
    target_kind text,
    target_id uuid,
    emoji text,
    total_count int,
    my_reacted boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;

    return query
    select 'chat'::text, chat_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where chat_message_id = any(chat_ids)
    group by chat_message_id, emoji

    union all

    select 'video'::text, video_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where video_message_id = any(video_ids)
    group by video_message_id, emoji;
end;
$$;

grant execute on function public.ping_message_reactions(uuid[], uuid[]) to authenticated;

-- 8. RPC: mark room read
create or replace function public.ping_mark_room_read(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    current_map jsonb;
begin
    if me is null then raise exception 'auth required'; end if;

    select last_read_chat_at into current_map from public.profiles where id = me;
    if current_map is null then current_map := '{}'::jsonb; end if;

    update public.profiles
       set last_read_chat_at = current_map || jsonb_build_object(room_uuid::text, to_jsonb(now()))
     where id = me;
end;
$$;

grant execute on function public.ping_mark_room_read(uuid) to authenticated;

-- 9. RPC: unread chat counts
create or replace function public.ping_unread_chat_counts()
returns table (room_id uuid, unread_count int)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    read_map jsonb;
begin
    if me is null then raise exception 'auth required'; end if;
    select last_read_chat_at into read_map from public.profiles where id = me;
    if read_map is null then read_map := '{}'::jsonb; end if;

    return query
    select cm.room_id,
           count(*)::int as unread_count
    from public.chat_messages cm
    join public.room_members rm on rm.room_id = cm.room_id and rm.user_id = me
    where cm.sender_uid <> me
      and cm.created_at > coalesce(
            (read_map ->> cm.room_id::text)::timestamptz,
            'epoch'::timestamptz
          )
    group by cm.room_id;
end;
$$;

grant execute on function public.ping_unread_chat_counts() to authenticated;

-- 10. RPC: delete chat (sender only)
create or replace function public.ping_delete_chat(chat_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner uuid;
begin
    if me is null then raise exception 'auth required'; end if;
    select sender_uid into owner from public.chat_messages where id = chat_uuid;
    if owner is null then return; end if;
    if owner <> me then raise exception 'only sender can delete'; end if;
    delete from public.chat_messages where id = chat_uuid;
end;
$$;

grant execute on function public.ping_delete_chat(uuid) to authenticated;

-- 11. Cleanup: 30d for chat + reactions
create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    msg_record record;
begin
    -- Messages: 30d
    for msg_record in
        select m.id, m.video_url, m.sender_uid
        from public.messages m
        where m.created_at < now() - interval '30 days'
    loop
        delete from storage.objects
        where bucket_id = 'ping-videos' and name = msg_record.video_url;
        delete from public.messages where id = msg_record.id;
    end loop;

    -- Chat: 30d (cascades reactions via FK)
    delete from public.chat_messages where created_at < now() - interval '30 days';

    -- Orphan reactions (target deleted): cleanup safety
    delete from public.message_reactions
    where chat_message_id is null and video_message_id is null;

    -- Invitations / links: 7d
    delete from public.invitations where expires_at < now();
    delete from public.invite_links where expires_at < now();
end;
$$;

-- 12. Realtime publication (for Supabase Realtime)
alter publication supabase_realtime add table public.chat_messages;
alter publication supabase_realtime add table public.message_reactions;
```

- [ ] **Step 2: Apply migration**

```bash
./scripts/supabase-ping.sh db push
```

Expected: success. If `add table public.chat_messages` to publication fails because publication doesn't exist on this project, that's OK — Realtime will fall back to polling. Ignore that error and continue.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260522000100_chat_and_reactions.sql
git commit -m "feat(db): chat_messages + reactions + reply + RPC suite"
```

---

## Phase B — Swift 모델

### Task B1: ChatMessage + MessageReaction + TimelineItem (TDD)

**Files:**
- Modify: `Ping/Core/Models.swift`
- Test: `PingTests/ChatMessageCodingTests.swift` (create)

- [ ] **Step 1: Write failing test**

Create `PingTests/ChatMessageCodingTests.swift`:

```swift
import XCTest
@testable import Ping

final class ChatMessageCodingTests: XCTestCase {
    func test_decode_minimalChat() throws {
        let json = """
        {
          "id": "c1",
          "room_id": "r1",
          "sender_uid": "u1",
          "sender_nickname": "alice",
          "body": "hello",
          "created_at": "2026-05-22T10:00:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let msg = try dec.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.id, "c1")
        XCTAssertEqual(msg.body, "hello")
        XCTAssertNil(msg.replyToChatId)
        XCTAssertNil(msg.replyToVideoId)
    }

    func test_decode_chatWithReply() throws {
        let json = """
        {
          "id": "c2",
          "room_id": "r1",
          "sender_uid": "u2",
          "sender_nickname": "bob",
          "body": "thanks",
          "reply_to_chat_id": "c1",
          "created_at": "2026-05-22T10:01:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let msg = try dec.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(msg.replyToChatId, "c1")
        XCTAssertNil(msg.replyToVideoId)
    }
}
```

Add the test file to Xcode project (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase entries — pattern from prior tasks).

- [ ] **Step 2: Run test (should fail compile)**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/ChatMessageCodingTests
```

Expected: FAIL — `ChatMessage` not defined.

- [ ] **Step 3: Add ChatMessage + MessageReaction + TimelineItem in Models.swift**

In `Ping/Core/Models.swift`, append:

```swift
struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String?
    var roomId: String
    var senderUid: String
    var senderNickname: String
    var body: String
    var replyToChatId: String?
    var replyToVideoId: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderUid = "sender_uid"
        case senderNickname = "sender_nickname"
        case body
        case replyToChatId = "reply_to_chat_id"
        case replyToVideoId = "reply_to_video_id"
        case createdAt = "created_at"
    }

    init(
        id: String? = nil,
        roomId: String,
        senderUid: String,
        senderNickname: String,
        body: String,
        replyToChatId: String? = nil,
        replyToVideoId: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.senderUid = senderUid
        self.senderNickname = senderNickname
        self.body = body
        self.replyToChatId = replyToChatId
        self.replyToVideoId = replyToVideoId
        self.createdAt = createdAt
    }
}

struct MessageReaction: Codable, Hashable, Identifiable {
    enum TargetKind: String, Codable {
        case chat
        case video
    }

    var targetKind: TargetKind
    var targetId: String
    var emoji: String
    var totalCount: Int
    var myReacted: Bool

    var id: String { "\(targetKind.rawValue):\(targetId):\(emoji)" }

    enum CodingKeys: String, CodingKey {
        case targetKind = "target_kind"
        case targetId = "target_id"
        case emoji
        case totalCount = "total_count"
        case myReacted = "my_reacted"
    }
}

enum TimelineItem: Identifiable, Hashable {
    case video(VideoMessage)
    case chat(ChatMessage)

    var id: String {
        switch self {
        case .video(let m): return "video:" + (m.id ?? UUID().uuidString)
        case .chat(let m): return "chat:" + (m.id ?? UUID().uuidString)
        }
    }

    var createdAt: Date? {
        switch self {
        case .video(let m): return m.createdAt
        case .chat(let m): return m.createdAt
        }
    }

    var senderUid: String {
        switch self {
        case .video(let m): return m.senderUid
        case .chat(let m): return m.senderUid
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/ChatMessageCodingTests
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Ping/Core/Models.swift PingTests/ChatMessageCodingTests.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(models): ChatMessage + MessageReaction + TimelineItem"
```

---

## Phase C — Service 계층

### Task C1: ChatMessageService

**Files:**
- Create: `Ping/Backend/ChatMessageService.swift`

- [ ] **Step 1: Create ChatMessageService**

```swift
import Foundation

@MainActor
final class ChatMessageService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func sendChat(roomId: String, body: String, replyToChatId: String? = nil, replyToVideoId: String? = nil) async throws -> String {
        var rpcBody: [String: Any] = [
            "room_uuid": roomId,
            "body_text": body
        ]
        if let replyToChatId { rpcBody["reply_chat_uuid"] = replyToChatId }
        if let replyToVideoId { rpcBody["reply_video_uuid"] = replyToVideoId }
        return try await client.rpcValue("ping_send_chat", body: rpcBody)
    }

    func roomChatMessages(roomId: String, beforeTimestamp: Date? = nil, limit: Int = 50) async throws -> [ChatMessage] {
        var rpcBody: [String: Any] = [
            "room_uuid": roomId,
            "page_limit": limit
        ]
        if let beforeTimestamp {
            rpcBody["before_ts"] = ISO8601DateFormatter.shared.string(from: beforeTimestamp)
        }
        return try await client.rpcArray("ping_room_chat_messages", body: rpcBody)
    }

    func deleteChat(messageId: String) async throws {
        try await client.rpcVoid("ping_delete_chat", body: ["chat_uuid": messageId])
    }

    func markRoomRead(roomId: String) async throws {
        try await client.rpcVoid("ping_mark_room_read", body: ["room_uuid": roomId])
    }

    func unreadChatCounts() async throws -> [String: Int] {
        struct Row: Codable {
            let room_id: String
            let unread_count: Int
        }
        let rows: [Row] = try await client.rpcArray("ping_unread_chat_counts")
        var map: [String: Int] = [:]
        for r in rows { map[r.room_id] = r.unread_count }
        return map
    }
}
```

Add to Xcode project pbxproj entries (Ping target, Backend group).

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ping/Backend/ChatMessageService.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ChatMessageService — send/list/delete/read marker RPCs"
```

---

### Task C2: ReactionService

**Files:**
- Create: `Ping/Backend/ReactionService.swift`

- [ ] **Step 1: Create ReactionService**

```swift
import Foundation

@MainActor
final class ReactionService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Returns true if the reaction was added, false if it was removed (toggle).
    @discardableResult
    func toggle(target kind: MessageReaction.TargetKind, targetId: String, emoji: String) async throws -> Bool {
        let result: Bool = try await client.rpcValue("ping_react", body: [
            "target_kind": kind.rawValue,
            "target_uuid": targetId,
            "emoji_text": emoji
        ])
        return result
    }

    func reactions(chatIds: [String], videoIds: [String]) async throws -> [MessageReaction] {
        try await client.rpcArray("ping_message_reactions", body: [
            "chat_ids": chatIds,
            "video_ids": videoIds
        ])
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/Backend/ReactionService.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ReactionService — toggle + aggregate fetch"
```

---

## Phase D — Realtime 인프라

### Task D1: supabase-swift SPM 의존성 추가

**Files:**
- Modify: `project.yml` — add packages section

- [ ] **Step 1: Add to project.yml**

Read current `project.yml` to find existing packages section. Add (or extend) a `packages` block at top-level (alongside `name`, `options`, `settings`, `targets`):

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.5.0"
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.0.0"
  Supabase:
    url: https://github.com/supabase/supabase-swift
    from: "2.20.0"
```

(Sparkle and KeyboardShortcuts entries already exist — preserve them exactly. Only ADD the `Supabase` entry. Use `from: "2.20.0"` as a lower bound that includes Realtime module support.)

Under the `Ping` target's `dependencies` section, add:

```yaml
    dependencies:
      - package: Sparkle
      - package: KeyboardShortcuts
      - package: Supabase
        product: Realtime
```

(Preserve existing Sparkle/KeyboardShortcuts dependencies. Just ADD the Supabase one with product Realtime.)

- [ ] **Step 2: Regenerate Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 3: Resolve packages + build**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" -resolvePackageDependencies
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED. Package will resolve from Swift Package Manager registry.

If package resolution fails (network, version), report BLOCKED with the exact error.

- [ ] **Step 4: Commit**

```bash
git add project.yml Ping.xcodeproj
git commit -m "build(spm): add Supabase Realtime dependency"
```

---

### Task D2: ChatRealtimeService

**Files:**
- Create: `Ping/Backend/ChatRealtimeService.swift`

Realtime via `supabase-swift`'s `Realtime` module. Postgres CDC on `chat_messages` and `message_reactions` filtered by room_id list.

- [ ] **Step 1: Implement ChatRealtimeService with polling fallback**

```swift
import Foundation
import Combine
@preconcurrency import Realtime

@MainActor
final class ChatRealtimeService: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case fallbackPolling
    }

    enum Event {
        case chatInserted(ChatMessage)
        case chatDeleted(messageId: String, roomId: String)
        case reactionChanged(targetKind: MessageReaction.TargetKind, targetId: String, emoji: String)
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var lastEvent: Event?

    private var realtime: RealtimeClient?
    private var channels: [RealtimeChannel] = []
    private var subscribedRoomIds: Set<String> = []
    private var pollingTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    private let chatService: ChatMessageService
    private let reactionService: ReactionService
    private var seenChatIds: Set<String> = []

    init(
        chatService: ChatMessageService = ChatMessageService(),
        reactionService: ReactionService = ReactionService()
    ) {
        self.chatService = chatService
        self.reactionService = reactionService
    }

    func subscribe(roomIds: [String], supabaseURL: URL, anonKey: String, accessToken: String?) async {
        guard !roomIds.isEmpty else {
            await unsubscribeAll()
            return
        }
        subscribedRoomIds = Set(roomIds)
        connectionState = .connecting
        await tearDownRealtime()

        let endpoint = supabaseURL.appendingPathComponent("realtime/v1")
        let options = RealtimeClientOptions(
            headers: ["apikey": anonKey],
            accessToken: { accessToken }
        )
        let client = RealtimeClient(endpoint, options: options)
        realtime = client

        for roomId in roomIds {
            let channel = client.channel("public:chat_messages:room_id=eq.\(roomId)")
            channel.on(.insert) { [weak self] message in
                Task { @MainActor in self?.handleChatInsert(message.payload) }
            }
            channel.on(.delete) { [weak self] message in
                Task { @MainActor in self?.handleChatDelete(message.payload) }
            }
            channels.append(channel)

            let reactionChannel = client.channel("public:message_reactions:room_id=eq.\(roomId)")
            reactionChannel.on(.insert) { [weak self] message in
                Task { @MainActor in self?.handleReactionChange(message.payload) }
            }
            reactionChannel.on(.delete) { [weak self] message in
                Task { @MainActor in self?.handleReactionChange(message.payload) }
            }
            channels.append(reactionChannel)
        }

        client.onOpen { [weak self] in
            Task { @MainActor in
                self?.connectionState = .connected
                self?.reconnectAttempt = 0
                self?.stopPollingFallback()
            }
        }
        client.onError { [weak self] _, _ in
            Task { @MainActor in self?.handleDisconnect() }
        }
        client.onClose { [weak self] in
            Task { @MainActor in self?.handleDisconnect() }
        }

        do {
            try await client.connect()
            for channel in channels {
                try await channel.subscribe()
            }
        } catch {
            NSLog("Realtime subscribe failed: \(error)")
            handleDisconnect()
        }
    }

    func unsubscribeAll() async {
        subscribedRoomIds.removeAll()
        stopPollingFallback()
        await tearDownRealtime()
        connectionState = .disconnected
    }

    private func tearDownRealtime() async {
        for channel in channels {
            try? await channel.unsubscribe()
        }
        channels.removeAll()
        try? await realtime?.disconnect()
        realtime = nil
    }

    private func handleChatInsert(_ payload: [String: Any]) {
        guard let dict = payload["record"] as? [String: Any] else { return }
        if let msg = decodeChatMessage(dict), let id = msg.id, !seenChatIds.contains(id) {
            seenChatIds.insert(id)
            lastEvent = .chatInserted(msg)
        }
    }

    private func handleChatDelete(_ payload: [String: Any]) {
        guard let dict = payload["old_record"] as? [String: Any],
              let id = dict["id"] as? String,
              let roomId = dict["room_id"] as? String else { return }
        lastEvent = .chatDeleted(messageId: id, roomId: roomId)
    }

    private func handleReactionChange(_ payload: [String: Any]) {
        let dict = (payload["record"] as? [String: Any]) ?? (payload["old_record"] as? [String: Any]) ?? [:]
        let chatId = dict["chat_message_id"] as? String
        let videoId = dict["video_message_id"] as? String
        let emoji = dict["emoji"] as? String ?? ""
        if let chatId {
            lastEvent = .reactionChanged(targetKind: .chat, targetId: chatId, emoji: emoji)
        } else if let videoId {
            lastEvent = .reactionChanged(targetKind: .video, targetId: videoId, emoji: emoji)
        }
    }

    private func decodeChatMessage(_ dict: [String: Any]) -> ChatMessage? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChatMessage.self, from: data)
    }

    private func handleDisconnect() {
        guard connectionState != .fallbackPolling else { return }
        connectionState = .fallbackPolling
        startPollingFallback()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(Double(reconnectAttempt) * 2.0, 20.0)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.subscribedRoomIds.isEmpty else { return }
            // Caller must re-invoke subscribe with fresh token. For now just attempt reconnect via stored client.
            // No-op here; AppDelegate's roomObserverTask re-invocation will handle full re-subscribe.
        }
    }

    private func startPollingFallback() {
        pollingTask?.cancel()
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let roomIds = await MainActor.run { Array(self.subscribedRoomIds) }
                for roomId in roomIds {
                    if let messages = try? await self.chatService.roomChatMessages(roomId: roomId, limit: 20) {
                        for msg in messages.reversed() {
                            await MainActor.run {
                                guard let id = msg.id, !self.seenChatIds.contains(id) else { return }
                                self.seenChatIds.insert(id)
                                self.lastEvent = .chatInserted(msg)
                            }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func stopPollingFallback() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/Backend/ChatRealtimeService.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ChatRealtimeService — Supabase Realtime + polling fallback"
```

If the Supabase Realtime API surface differs from what this code assumes (e.g., `channel.on(.insert)` syntax), adapt to match the resolved package version. If the API is incompatible, replace the Realtime block with polling-only (mark connectionState = .fallbackPolling permanently and use only the polling path). Commit either way and report which mode is active.

---

## Phase E — HistoryViewModel 통합 타임라인

### Task E1: HistoryViewModel timeline merge

**Files:**
- Modify: `Ping/UI/History/HistoryViewModel.swift`
- Test: `PingTests/HistoryViewModelTests.swift` (extend)

- [ ] **Step 1: Extend tests for merged timeline**

In `PingTests/HistoryViewModelTests.swift`, add:

```swift
    func test_mergeTimeline_interleavesByTimestamp() {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()

        let video = VideoMessage(
            id: "v1", roomId: "r", senderUid: "u",
            receiverUid: "rcv", senderNickname: "n",
            videoId: "v", videoUrl: "u/v.mp4", durationMs: 3000,
            mirrorPosition: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            status: .uploaded,
            createdAt: today,
            expiresAt: today.addingTimeInterval(60),
            captureMode: .faceOnly,
            aspectRatio: nil
        )
        let chat = ChatMessage(
            id: "c1", roomId: "r", senderUid: "u",
            senderNickname: "n", body: "hi",
            createdAt: today.addingTimeInterval(10)
        )

        let groups = HistoryViewModel.groupTimelineByDay(
            videos: [video],
            chats: [chat],
            calendar: cal
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.map(\.id), ["chat:c1", "video:v1"])
    }
```

- [ ] **Step 2: Run to verify fail**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/HistoryViewModelTests/test_mergeTimeline_interleavesByTimestamp
```

Expected: FAIL — `groupTimelineByDay` not defined.

- [ ] **Step 3: Refactor HistoryViewModel**

Replace `Ping/UI/History/HistoryViewModel.swift` entirely:

```swift
import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    struct DayGroup: Identifiable {
        let date: Date
        let items: [TimelineItem]
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    @Published var selectedRoomId: String?
    @Published var groups: [DayGroup] = []
    @Published var isLoading: Bool = false
    @Published var expandedMessageId: String?
    @Published var replyTarget: ReplyTarget?
    @Published var reactionsByTargetId: [String: [String: ReactionAggregate]] = [:] // targetKey -> emoji -> agg

    struct ReactionAggregate: Hashable {
        let emoji: String
        let count: Int
        let myReacted: Bool
    }

    enum ReplyTarget: Hashable {
        case chat(id: String, sender: String, preview: String)
        case video(id: String, sender: String, captureMode: CaptureMode)
    }

    let inlineController = InlinePlayerController()

    private let messageService: MessageService
    private let chatService: ChatMessageService
    private let reactionService: ReactionService
    private var loadedVideos: [VideoMessage] = []
    private var loadedChats: [ChatMessage] = []

    init(
        messageService: MessageService,
        chatService: ChatMessageService = ChatMessageService(),
        reactionService: ReactionService = ReactionService()
    ) {
        self.messageService = messageService
        self.chatService = chatService
        self.reactionService = reactionService
    }

    func selectRoom(_ roomId: String) async {
        selectedRoomId = roomId
        loadedVideos = []
        loadedChats = []
        groups = []
        reactionsByTargetId = [:]
        await loadMore()
        try? await chatService.markRoomRead(roomId: roomId)
    }

    func loadMore() async {
        guard let roomId = selectedRoomId, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let videosTask = messageService.roomMessages(roomId: roomId, beforeTimestamp: loadedVideos.last?.createdAt, limit: 50)
        async let chatsTask = chatService.roomChatMessages(roomId: roomId, beforeTimestamp: loadedChats.last?.createdAt, limit: 50)

        do {
            let (videos, chats) = try await (videosTask, chatsTask)
            loadedVideos.append(contentsOf: videos)
            loadedChats.append(contentsOf: chats)
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            await refreshReactions()
        } catch {
            NSLog("History load failed: \(error)")
        }
    }

    func refreshReactions() async {
        let chatIds = loadedChats.compactMap(\.id)
        let videoIds = loadedVideos.compactMap(\.id)
        guard !chatIds.isEmpty || !videoIds.isEmpty else { return }
        do {
            let reactions = try await reactionService.reactions(chatIds: chatIds, videoIds: videoIds)
            var map: [String: [String: ReactionAggregate]] = [:]
            for r in reactions {
                let key = "\(r.targetKind.rawValue):\(r.targetId)"
                map[key, default: [:]][r.emoji] = ReactionAggregate(emoji: r.emoji, count: r.totalCount, myReacted: r.myReacted)
            }
            reactionsByTargetId = map
        } catch {
            NSLog("Reactions fetch failed: \(error)")
        }
    }

    func handleRealtimeEvent(_ event: ChatRealtimeService.Event) {
        switch event {
        case .chatInserted(let msg):
            guard msg.roomId == selectedRoomId else { return }
            if !loadedChats.contains(where: { $0.id == msg.id }) {
                loadedChats.append(msg)
                groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            }
        case .chatDeleted(let id, _):
            loadedChats.removeAll { $0.id == id }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        case .reactionChanged:
            Task { await refreshReactions() }
        }
    }

    func sendChat(body: String) async {
        guard let roomId = selectedRoomId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var replyChatId: String?
        var replyVideoId: String?
        switch replyTarget {
        case .chat(let id, _, _): replyChatId = id
        case .video(let id, _, _): replyVideoId = id
        case .none: break
        }

        do {
            _ = try await chatService.sendChat(roomId: roomId, body: trimmed, replyToChatId: replyChatId, replyToVideoId: replyVideoId)
            replyTarget = nil
            await refreshReactions()
        } catch {
            NSLog("Send chat failed: \(error)")
        }
    }

    func toggleReaction(target: MessageReaction.TargetKind, targetId: String, emoji: String) async {
        do {
            _ = try await reactionService.toggle(target: target, targetId: targetId, emoji: emoji)
            await refreshReactions()
        } catch {
            NSLog("Toggle reaction failed: \(error)")
        }
    }

    func deleteChat(messageId: String) async {
        do {
            try await chatService.deleteChat(messageId: messageId)
            loadedChats.removeAll { $0.id == messageId }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        } catch {
            NSLog("Delete chat failed: \(error)")
        }
    }

    static func groupTimelineByDay(videos: [VideoMessage], chats: [ChatMessage], calendar: Calendar) -> [DayGroup] {
        var items: [TimelineItem] = []
        items.append(contentsOf: videos.map(TimelineItem.video))
        items.append(contentsOf: chats.map(TimelineItem.chat))
        let sorted = items.compactMap { item -> (Date, TimelineItem)? in
            guard let d = item.createdAt else { return nil }
            return (d, item)
        }.sorted { $0.0 > $1.0 }

        var groups: [DayGroup] = []
        var currentDate: Date?
        var currentItems: [TimelineItem] = []
        for (date, item) in sorted {
            let day = calendar.startOfDay(for: date)
            if day != currentDate {
                if let currentDate {
                    groups.append(DayGroup(date: currentDate, items: currentItems))
                }
                currentDate = day
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }
        if let currentDate {
            groups.append(DayGroup(date: currentDate, items: currentItems))
        }
        return groups
    }

    // Existing save/delete methods for video (preserve API for RoomTimelineView callers)
    func save(message: VideoMessage, cacheService: HistoryCacheService, currentUid: String?) async {
        guard let id = message.id else { return }
        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            let isMine = message.senderUid == currentUid
            do {
                if isMine {
                    let url = LocalArchive.sentURL(for: cached.lastPathComponent, partnerName: message.senderNickname)
                    try? FileManager.default.copyItem(at: cached, to: url)
                } else {
                    let url = LocalArchive.receivedURL(for: cached.lastPathComponent, partnerName: message.senderNickname)
                    try? FileManager.default.copyItem(at: cached, to: url)
                }
            }
        }
    }

    func delete(message: VideoMessage, currentUid: String?) async {
        guard let id = message.id else { return }
        let isMine = message.senderUid == currentUid
        do {
            if isMine {
                try await messageService.deleteMessage(messageId: id)
            } else {
                try await messageService.hideMessageForReceiver(messageId: id)
            }
            loadedVideos.removeAll { $0.id == id }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        } catch {
            NSLog("Delete failed: \(error)")
        }
    }
}
```

If `LocalArchive.sentURL`/`receivedURL` signatures differ (read `Ping/Capture/LocalArchive.swift` first), adapt the `save` method to match.

- [ ] **Step 4: Run test**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```

Expected: all tests pass including new `test_mergeTimeline_interleavesByTimestamp`.

- [ ] **Step 5: Commit**

```bash
git add Ping/UI/History/HistoryViewModel.swift PingTests/HistoryViewModelTests.swift
git commit -m "feat(history): integrated timeline (video + chat) + reactions + reply state"
```

---

## Phase F — UI 컴포넌트

### Task F1: ChatMessageRowView

**Files:**
- Create: `Ping/UI/History/ChatMessageRowView.swift`

- [ ] **Step 1: Create row view**

```swift
import SwiftUI

struct ChatMessageRowView: View {
    let message: ChatMessage
    let isMine: Bool
    let showsSender: Bool
    let replyPreview: ReplyPreview?
    let reactions: [HistoryViewModel.ReactionAggregate]
    let onReply: () -> Void
    let onReact: () -> Void
    let onDelete: () -> Void
    let onToggleReaction: (String) -> Void

    @State private var isHovered: Bool = false

    enum ReplyPreview {
        case chat(sender: String, body: String)
        case video(sender: String, captureMode: CaptureMode)

        var senderName: String {
            switch self {
            case .chat(let s, _): return s
            case .video(let s, _): return s
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isMine { Spacer(minLength: 40) }

            if !isMine && isHovered { hoverActions }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if showsSender && !isMine {
                    Text(message.senderNickname)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if let replyPreview {
                    replyQuote(replyPreview)
                }
                bubble
                if !reactions.isEmpty {
                    reactionStrip
                }
            }
            .frame(maxWidth: 360, alignment: isMine ? .trailing : .leading)

            if isMine && isHovered { hoverActions }

            if !isMine { Spacer(minLength: 40) }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var bubble: some View {
        Text(message.body)
            .font(.body)
            .foregroundStyle(isMine ? .white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isMine ? Color.accentColor : Color.gray.opacity(0.18))
            )
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func replyQuote(_ preview: ReplyPreview) -> some View {
        let text: String
        switch preview {
        case .chat(_, let body):
            text = body.prefix(60) + (body.count > 60 ? "…" : "")
        case .video(_, let mode):
            text = mode == .faceOnly ? "🎥 얼굴 영상" : "🖥 화면+얼굴 영상"
        }
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.senderName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var reactionStrip: some View {
        HStack(spacing: 4) {
            ForEach(reactions, id: \.emoji) { agg in
                Button(action: { onToggleReaction(agg.emoji) }) {
                    HStack(spacing: 2) {
                        Text(agg.emoji)
                        if agg.count > 1 {
                            Text("\(agg.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(agg.myReacted ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button(action: onReply) {
                Image(systemName: "arrowshape.turn.up.left").imageScale(.small)
            }.buttonStyle(.plain)
            Button(action: onReact) {
                Image(systemName: "face.smiling").imageScale(.small)
            }.buttonStyle(.plain)
            if isMine {
                Button(action: onDelete) {
                    Image(systemName: "trash").imageScale(.small)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .foregroundStyle(.secondary)
    }
}
```

Add to Xcode project (History group, Sources phase).

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/UI/History/ChatMessageRowView.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ChatMessageRowView with reply quote + reactions"
```

---

### Task F2: ChatComposerView (input + reply preview)

**Files:**
- Create: `Ping/UI/History/ChatComposerView.swift`

- [ ] **Step 1: Implement composer**

```swift
import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let replyTarget: HistoryViewModel.ReplyTarget?
    let onCancelReply: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let replyTarget {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .foregroundStyle(.secondary)
                    Text(replyPreviewText(replyTarget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onCancelReply) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.08))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 32, maxHeight: 132)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onKeyPress(.return, phases: .down) { event in
                        if event.modifiers.contains(.command) {
                            onSend()
                            return .handled
                        }
                        return .ignored
                    }
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                        .background(canSend ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= 2000
    }

    private func replyPreviewText(_ target: HistoryViewModel.ReplyTarget) -> String {
        switch target {
        case .chat(_, let sender, let preview):
            return "\(sender): \(preview)"
        case .video(_, let sender, let mode):
            let label = mode == .faceOnly ? "얼굴 영상" : "화면+얼굴 영상"
            return "\(sender): \(label)"
        }
    }
}
```

Add to Xcode project.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/UI/History/ChatComposerView.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ChatComposerView — multiline input + reply preview + Cmd+Enter"
```

---

### Task F3: ReactionPickerView (quick set + 더보기)

**Files:**
- Create: `Ping/UI/History/ReactionPickerView.swift`

- [ ] **Step 1: Implement picker**

```swift
import SwiftUI
import AppKit

struct ReactionPickerView: View {
    let onPick: (String) -> Void
    let onMore: () -> Void

    static let quickSet = ["❤️", "👍", "👎", "😂", "‼️", "❓"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.quickSet, id: \.self) { emoji in
                Button(action: { onPick(emoji) }) {
                    Text(emoji).font(.title3)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 18)
            Button(action: onMore) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }

    static func openSystemEmojiPicker() {
        NSApp.orderFrontCharacterPalette(nil)
    }
}
```

Add to Xcode project.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/UI/History/ReactionPickerView.swift Ping.xcodeproj/project.pbxproj
git commit -m "feat(chat): ReactionPickerView — quick set + system emoji palette"
```

---

### Task F4: RoomTimelineView 통합 + reactions for video + composer

**Files:**
- Modify: `Ping/UI/History/RoomTimelineView.swift`
- Modify: `Ping/UI/History/MessageRowView.swift` — accept reactions, reply action

- [ ] **Step 1: Extend MessageRowView with reactions/reply**

Replace `Ping/UI/History/MessageRowView.swift`:

```swift
import SwiftUI

struct MessageRowView: View {
    let message: VideoMessage
    let isMine: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let cacheService: HistoryCacheService
    @ObservedObject var inlineController: InlinePlayerController
    let reactions: [HistoryViewModel.ReactionAggregate]
    let onReply: () -> Void
    let onReact: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onToggleReaction: (String) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            if isMine { Spacer() }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if isExpanded {
                    InlinePlayerView(message: message, cacheService: cacheService, controller: inlineController)
                } else {
                    thumbnail
                }
                metadata
                if !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions, id: \.emoji) { agg in
                            Button(action: { onToggleReaction(agg.emoji) }) {
                                HStack(spacing: 2) {
                                    Text(agg.emoji)
                                    if agg.count > 1 {
                                        Text("\(agg.count)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agg.myReacted ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if isHovered && !isExpanded {
                HStack(spacing: 6) {
                    Button(action: onReply) { Image(systemName: "arrowshape.turn.up.left").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onReact) { Image(systemName: "face.smiling").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onSave) { Image(systemName: "arrow.down.circle").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onDelete) { Image(systemName: "trash").imageScale(.small) }.buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
            if !isMine { Spacer() }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var thumbnail: some View {
        Group {
            if message.captureMode == .faceOnly {
                Circle().fill(Color.gray.opacity(0.3)).frame(width: 60, height: 60)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
                    .aspectRatio(message.aspectRatio ?? 1.78, contentMode: .fit)
                    .frame(maxWidth: 90)
            }
        }
        .overlay(Image(systemName: "play.fill").foregroundStyle(.white))
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if message.captureMode == .screenFace {
                Image(systemName: "rectangle.fill").font(.caption2)
            } else {
                Image(systemName: "circle.fill").font(.caption2)
            }
            if let date = message.createdAt {
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Replace RoomTimelineView with unified timeline**

Replace `Ping/UI/History/RoomTimelineView.swift`:

```swift
import SwiftUI

struct RoomTimelineView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let cacheService: HistoryCacheService
    @ObservedObject var appState: AppState

    @State private var draft: String = ""
    @State private var reactionPickerTargetKey: String?
    @State private var reactionPickerTargetKind: MessageReaction.TargetKind?
    @State private var reactionPickerTargetId: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.groups) { group in
                            Section(header: dayHeader(group.date)) {
                                ForEach(group.items) { item in
                                    rowFor(item: item)
                                        .id(item.id)
                                }
                            }
                        }
                        if viewModel.isLoading {
                            ProgressView().padding()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: viewModel.groups.first?.items.first?.id) { _ in
                    if let firstId = viewModel.groups.first?.items.first?.id {
                        withAnimation(.easeOut) { scrollProxy.scrollTo(firstId, anchor: .bottom) }
                    }
                }
            }

            ChatComposerView(
                draft: $draft,
                replyTarget: viewModel.replyTarget,
                onCancelReply: { viewModel.replyTarget = nil },
                onSend: {
                    let body = draft
                    draft = ""
                    Task { await viewModel.sendChat(body: body) }
                }
            )
        }
        .overlay(alignment: .top) {
            if let targetKey = reactionPickerTargetKey,
               let targetKind = reactionPickerTargetKind,
               let targetId = reactionPickerTargetId {
                ReactionPickerView(
                    onPick: { emoji in
                        Task { await viewModel.toggleReaction(target: targetKind, targetId: targetId, emoji: emoji) }
                        reactionPickerTargetKey = nil
                    },
                    onMore: {
                        ReactionPickerView.openSystemEmojiPicker()
                        reactionPickerTargetKey = nil
                    }
                )
                .onDisappear { _ = targetKey }
                .padding(.top, 60)
            }
        }
    }

    @ViewBuilder
    private func rowFor(item: TimelineItem) -> some View {
        let myUid = appState.currentUser?.id
        switch item {
        case .video(let v):
            let key = "video:" + (v.id ?? "")
            let aggs = (viewModel.reactionsByTargetId[key] ?? [:]).values.sorted(by: { $0.count > $1.count })
            MessageRowView(
                message: v,
                isMine: v.senderUid == myUid,
                isExpanded: viewModel.expandedMessageId == v.id,
                onTap: {
                    if viewModel.expandedMessageId == v.id {
                        viewModel.expandedMessageId = nil
                    } else {
                        viewModel.expandedMessageId = v.id
                    }
                },
                cacheService: cacheService,
                inlineController: viewModel.inlineController,
                reactions: Array(aggs),
                onReply: {
                    viewModel.replyTarget = .video(id: v.id ?? "", sender: v.senderNickname, captureMode: v.captureMode)
                },
                onReact: {
                    reactionPickerTargetKey = key
                    reactionPickerTargetKind = .video
                    reactionPickerTargetId = v.id
                },
                onSave: { Task { await viewModel.save(message: v, cacheService: cacheService, currentUid: myUid) } },
                onDelete: { Task { await viewModel.delete(message: v, currentUid: myUid) } },
                onToggleReaction: { emoji in
                    guard let vid = v.id else { return }
                    Task { await viewModel.toggleReaction(target: .video, targetId: vid, emoji: emoji) }
                }
            )
        case .chat(let c):
            let key = "chat:" + (c.id ?? "")
            let aggs = (viewModel.reactionsByTargetId[key] ?? [:]).values.sorted(by: { $0.count > $1.count })
            let preview = replyPreview(for: c)
            ChatMessageRowView(
                message: c,
                isMine: c.senderUid == myUid,
                showsSender: appState.rooms.first(where: { $0.id == c.roomId })?.memberUids.count ?? 0 >= 3,
                replyPreview: preview,
                reactions: Array(aggs),
                onReply: {
                    viewModel.replyTarget = .chat(id: c.id ?? "", sender: c.senderNickname, preview: c.body)
                },
                onReact: {
                    reactionPickerTargetKey = key
                    reactionPickerTargetKind = .chat
                    reactionPickerTargetId = c.id
                },
                onDelete: { Task { await viewModel.deleteChat(messageId: c.id ?? "") } },
                onToggleReaction: { emoji in
                    guard let cid = c.id else { return }
                    Task { await viewModel.toggleReaction(target: .chat, targetId: cid, emoji: emoji) }
                }
            )
        }
    }

    private func replyPreview(for chat: ChatMessage) -> ChatMessageRowView.ReplyPreview? {
        if let replyChatId = chat.replyToChatId,
           let target = findChat(by: replyChatId) {
            return .chat(sender: target.senderNickname, body: target.body)
        }
        if let replyVideoId = chat.replyToVideoId,
           let target = findVideo(by: replyVideoId) {
            return .video(sender: target.senderNickname, captureMode: target.captureMode)
        }
        return nil
    }

    private func findChat(by id: String) -> ChatMessage? {
        for group in viewModel.groups {
            for item in group.items {
                if case .chat(let c) = item, c.id == id { return c }
            }
        }
        return nil
    }

    private func findVideo(by id: String) -> VideoMessage? {
        for group in viewModel.groups {
            for item in group.items {
                if case .video(let v) = item, v.id == id { return v }
            }
        }
        return nil
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/UI/History/RoomTimelineView.swift Ping/UI/History/MessageRowView.swift
git commit -m "feat(history): unified timeline with chat rows + reactions + composer"
```

---

### Task F5: HistoryView wiring + Realtime hookup

**Files:**
- Modify: `Ping/UI/History/HistoryView.swift`
- Modify: `Ping/UI/History/HistoryWindow.swift`
- Modify: `Ping/AppDelegate.swift` — own ChatRealtimeService + subscribe lifecycle

- [ ] **Step 1: HistoryView observes realtime events**

Replace `Ping/UI/History/HistoryView.swift`:

```swift
import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var realtime: ChatRealtimeService
    let cacheService: HistoryCacheService

    @State private var keyMonitor: Any?
    @State private var expandedPlaybackWindow: ExpandedPlaybackWindow?

    var body: some View {
        HSplitView {
            HistorySidebar(rooms: appState.rooms, selectedRoomId: $viewModel.selectedRoomId)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
                .onChange(of: viewModel.selectedRoomId) { newId in
                    guard let id = newId else { return }
                    Task { await viewModel.selectRoom(id) }
                }

            if viewModel.selectedRoomId != nil {
                RoomTimelineView(viewModel: viewModel, cacheService: cacheService, appState: appState)
                    .frame(minWidth: 400)
            } else {
                VStack {
                    Text("좌측에서 룸을 선택하세요")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event) ? nil : event
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .onReceive(realtime.$lastEvent.compactMap { $0 }) { event in
            viewModel.handleRealtimeEvent(event)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let allItems = viewModel.groups.flatMap(\.items)
        let current = viewModel.expandedMessageId.flatMap { id in
            allItems.firstIndex(where: { $0.id.replacingOccurrences(of: "video:", with: "").replacingOccurrences(of: "chat:", with: "") == id })
        }

        switch event.keyCode {
        case 126:
            if let i = current, i > 0, case .video(let v) = allItems[i - 1] { viewModel.expandedMessageId = v.id }
            return true
        case 125:
            if let i = current, i + 1 < allItems.count, case .video(let v) = allItems[i + 1] { viewModel.expandedMessageId = v.id }
            return true
        case 36:
            viewModel.inlineController.replay()
            return true
        case 49:
            if let player = viewModel.inlineController.player,
               let id = viewModel.expandedMessageId,
               let video = allItems.compactMap({ if case .video(let v) = $0, v.id == id { return v } else { return nil } }).first,
               let screen = NSApp.keyWindow?.screen {
                let aspect: Double = video.captureMode == .screenFace ? (video.aspectRatio ?? 1.78) : 1.0
                let expanded = ExpandedPlaybackWindow(
                    player: player,
                    aspectRatio: aspect,
                    on: screen,
                    onDismiss: {
                        expandedPlaybackWindow?.orderOut(nil)
                        expandedPlaybackWindow = nil
                    }
                )
                expandedPlaybackWindow = expanded
                expanded.present()
            }
            return true
        case 53:
            if viewModel.expandedMessageId != nil {
                viewModel.expandedMessageId = nil
            } else {
                NSApp.keyWindow?.close()
            }
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: HistoryWindow accepts realtime service**

Replace `Ping/UI/History/HistoryWindow.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class HistoryWindow: NSWindow {
    init(
        appState: AppState,
        messageService: MessageService,
        cacheService: HistoryCacheService,
        realtime: ChatRealtimeService
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Ping 히스토리"
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        let viewModel = HistoryViewModel(messageService: messageService)
        let host = NSHostingView(rootView:
            HistoryView(appState: appState, viewModel: viewModel, realtime: realtime, cacheService: cacheService)
        )
        host.frame = contentView!.bounds
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)
    }
}
```

- [ ] **Step 3: AppDelegate owns ChatRealtimeService + subscribes lifecycle**

In `Ping/AppDelegate.swift`:

(a) Add property:
```swift
    private let chatRealtime = ChatRealtimeService()
```

(b) In `toggleHistory()`, pass `realtime: chatRealtime`:
```swift
        let window = HistoryWindow(
            appState: appState,
            messageService: messageService,
            cacheService: HistoryCacheService.shared,
            realtime: chatRealtime
        )
```

(c) After bootstrap (where `appState.rooms` becomes available — look for `roomObserverTask` body), invoke `chatRealtime.subscribe`:

In `startObservers(uid:opensRoomManagerWhenEmpty:)`, inside the `for await rooms in roomService.observeMyRooms(uid: uid)` loop, append:

```swift
                // Resubscribe Realtime to current room set
                Task { @MainActor in
                    let roomIds = rooms.compactMap(\.id)
                    let cfg = SupabaseClient.shared.config
                    let token = await SupabaseClient.shared.currentAccessToken()
                    await self.chatRealtime.subscribe(
                        roomIds: roomIds,
                        supabaseURL: cfg.url,
                        anonKey: cfg.anonKey,
                        accessToken: token
                    )
                }
```

If `SupabaseClient.shared.config` and `currentAccessToken()` don't exist by those names, find equivalents in `Ping/Backend/SupabaseClient.swift` (look for stored URL, anon key, session token retrieval). Adapt accordingly. If currently inaccessible, expose via small additions:

```swift
extension SupabaseClient {
    var configURL: URL { /* return stored url */ }
    var configAnonKey: String { /* return stored anon key */ }
    func currentAccessToken() async -> String? { /* return current session access token */ }
}
```

(d) In `applicationWillTerminate`, add:
```swift
        Task { await chatRealtime.unsubscribeAll() }
```

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
git add Ping/UI/History/HistoryView.swift Ping/UI/History/HistoryWindow.swift Ping/AppDelegate.swift Ping/Backend/SupabaseClient.swift
git commit -m "feat(history): wire HistoryView + HistoryWindow + AppDelegate to ChatRealtimeService"
```

If `xcodebuild test` fails because the new HistoryView API changed (HistoryView now requires `realtime:` param), update any other call site / preview to match. Most likely only `HistoryWindow` is the caller.

---

## Phase G — 알림

### Task G1: chat push notification + suppress + click handler

**Files:**
- Modify: `Ping/Notifications/LocalNotificationCenter.swift`
- Modify: `Ping/AppDelegate.swift`

- [ ] **Step 1: LocalNotificationCenter — chat notification**

Read current `Ping/Notifications/LocalNotificationCenter.swift`. Add (alongside existing `notifyIncomingMessage` or similar):

```swift
    func notifyIncomingChat(_ message: ChatMessage, roomName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(message.senderNickname) · \(roomName)"
        let body = message.body
        content.body = body.count > 200 ? String(body.prefix(200)) + "…" : body
        content.sound = .default
        content.userInfo = [
            "type": "chat",
            "chat_id": message.id ?? "",
            "room_id": message.roomId
        ]
        let request = UNNotificationRequest(identifier: "chat-\(message.id ?? UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    var onViewChatMessage: ((_ chatId: String, _ roomId: String) -> Void)?
```

In the existing `userNotificationCenter(_:didReceive:withCompletionHandler:)` delegate method, handle the `chat` type:

```swift
        if let type = response.notification.request.content.userInfo["type"] as? String,
           type == "chat",
           let chatId = response.notification.request.content.userInfo["chat_id"] as? String,
           let roomId = response.notification.request.content.userInfo["room_id"] as? String {
            onViewChatMessage?(chatId, roomId)
            completionHandler()
            return
        }
```

(Adapt to existing delegate signature.)

- [ ] **Step 2: AppDelegate wire chat notifications**

In `Ping/AppDelegate.swift`:

(a) Add property:
```swift
    private var notifiedChatMessageIds: Set<String> = []
```

(b) Subscribe to chat realtime events in `applicationDidFinishLaunching` or `startObservers`:

```swift
        Task { @MainActor in
            for await event in chatRealtime.$lastEvent.compactMap({ $0 }).values {
                self.handleChatRealtimeEvent(event)
            }
        }
```

(c) Implement:
```swift
    @MainActor
    private func handleChatRealtimeEvent(_ event: ChatRealtimeService.Event) {
        guard case .chatInserted(let msg) = event else { return }
        guard msg.senderUid != appState.currentUser?.id else { return }
        guard let id = msg.id, !notifiedChatMessageIds.contains(id) else { return }
        notifiedChatMessageIds.insert(id)
        if notifiedChatMessageIds.count > 500 {
            notifiedChatMessageIds = Set(notifiedChatMessageIds.suffix(500))
        }

        // Suppress if window is open and showing this room
        let suppressed = historyWindow != nil  // simple heuristic; refined check would need viewModel access
        if !suppressed {
            let roomName = appState.rooms.first(where: { $0.id == msg.roomId })?.name ?? "룸"
            LocalNotificationCenter.shared.notifyIncomingChat(msg, roomName: roomName)
        }
    }
```

(d) Wire click handler:

```swift
        LocalNotificationCenter.shared.onViewChatMessage = { [weak self] chatId, roomId in
            self?.openHistoryAndFocus(chatId: chatId, roomId: roomId)
        }

    private func openHistoryAndFocus(chatId: String, roomId: String) {
        if historyWindow == nil { toggleHistory() }
        // Selection / scroll will happen via HistoryViewModel; for now just open + select room.
        // The HistoryView's onChange(of: selectedRoomId) loads room messages, then Realtime / load brings the message into view.
        // Future enhancement: explicit scrollTo(chatId).
    }
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
git add Ping/Notifications/LocalNotificationCenter.swift Ping/AppDelegate.swift
git commit -m "feat(chat): push notification on incoming chat + click → open history"
```

---

## Phase H — client_events + 회귀 + release

### Task H1: client_events 인스트루멘테이션

**Files:**
- Modify: `Ping/UI/History/HistoryViewModel.swift`
- Modify: `Ping/Backend/ChatRealtimeService.swift`
- Modify: `Ping/AppDelegate.swift`

- [ ] **Step 1: Instrument send/react/notification**

In `Ping/UI/History/HistoryViewModel.swift` `sendChat`, after successful send:
```swift
            ClientEventService.shared.log("chat_sent", properties: [
                "room_id": roomId,
                "body_length": trimmed.count,
                "is_reply": (replyChatId != nil || replyVideoId != nil),
                "reply_kind": replyChatId != nil ? "chat" : (replyVideoId != nil ? "video" : "none")
            ])
```

In `toggleReaction`, after successful toggle:
```swift
            let added = try await reactionService.toggle(target: target, targetId: targetId, emoji: emoji)
            ClientEventService.shared.log(
                added ? "reaction_added" : "reaction_removed",
                properties: ["target_kind": target.rawValue, "emoji": emoji]
            )
```

In `selectRoom`, after `markRoomRead`:
```swift
            ClientEventService.shared.log("chat_received_view", properties: ["room_id": roomId])
```

In `ChatRealtimeService` connection state transitions:
```swift
// in handleDisconnect():
ClientEventService.shared.log("realtime_disconnected")

// in onOpen callback / connected branch:
ClientEventService.shared.log("realtime_reconnected", properties: ["after_seconds": reconnectAttempt * 2])
```

In `AppDelegate.openHistoryAndFocus`:
```swift
ClientEventService.shared.log("chat_notification_clicked", properties: ["room_id": roomId])
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
git add Ping/UI/History/HistoryViewModel.swift Ping/Backend/ChatRealtimeService.swift Ping/AppDelegate.swift
git commit -m "feat(analytics): chat + reaction + realtime event tracking"
```

---

### Task H2: 회귀 + release 0.3.0

**Files:**
- Modify: `project.yml` (MARKETING_VERSION 0.2.1 → 0.3.0, CURRENT_PROJECT_VERSION 8 → 9)
- Modify: `web/src/routes.tsx` (APP_VERSION + DOWNLOAD_URL)
- Modify: `README.md` (DMG filename)
- Modify: `PingTests/ReleaseVersionContractTests.swift`

- [ ] **Step 1: Bump version**

```bash
sed -i '' 's/MARKETING_VERSION: "0.2.1"/MARKETING_VERSION: "0.3.0"/; s/CURRENT_PROJECT_VERSION: "8"/CURRENT_PROJECT_VERSION: "9"/' project.yml
sed -i '' 's|0.2.1|0.3.0|g' web/src/routes.tsx README.md PingTests/ReleaseVersionContractTests.swift
sed -i '' 's/CURRENT_PROJECT_VERSION: "8"/CURRENT_PROJECT_VERSION: "9"/' PingTests/ReleaseVersionContractTests.swift
```

- [ ] **Step 2: Regenerate + final test**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```

Expected: all tests pass.

- [ ] **Step 3: Commit + tag**

```bash
git add project.yml web/src/routes.tsx README.md PingTests/ReleaseVersionContractTests.swift Ping.xcodeproj
git commit -m "release: 0.3.0"
git tag v0.3.0
```

- [ ] **Step 4: Build DMG**

```bash
osascript -e 'tell application "Ping" to quit' 2>/dev/null
pkill -f "Ping.app/Contents/MacOS/Ping" 2>/dev/null
./scripts/build-release.sh
```

Expected: `dist/Ping-v0.3.0.dmg` + appcast + deltas.

- [ ] **Step 5: Install + push**

```bash
rm -rf /Applications/Ping.app
ditto dist/dmg-root/Ping.app /Applications/Ping.app

git add web/public/appcast.xml web/public/downloads/Ping-v0.3.0.dmg web/public/downloads/Ping9-*.delta 2>/dev/null
git commit -m "release: 0.3.0 artifacts (DMG, appcast, deltas)"
git push origin main --tags

open /Applications/Ping.app
```

Verify launch with `pgrep -fl "Ping.app/Contents/MacOS/Ping"`.

---

## 완료 정의

- DB 마이그레이션 적용됨 (chat_messages, reactions, 10 RPCs)
- supabase-swift Realtime 모듈 통합 또는 polling-only fallback 모드 동작
- HistoryView가 영상+채팅 통합 타임라인 표시
- 채팅 입력 + reply + Cmd+Enter 전송 동작
- 반응 추가/제거 (quick set + 시스템 emoji picker)
- macOS 푸시 알림 (sender ≠ self, dedup) + 클릭 시 히스토리 자동 열기
- v0.3.0 tag pushed, /Applications/Ping.app 0.3.0
- 106+ tests pass

**Fallback 모드 보고**: Realtime 통합이 SDK 호환 문제로 실패하면 polling-only로 동작하고 다음 메시지를 commit message나 release note에 기록 — "Realtime fell back to polling (10s interval)". 그 외는 동일하게 작동.
