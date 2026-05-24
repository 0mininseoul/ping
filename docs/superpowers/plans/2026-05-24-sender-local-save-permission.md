# Sender Local Save Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let senders decide whether recipients can save the sender's videos locally, while preserving sender-owned local archive settings and cloud-backed history playback.

**Architecture:** Add an `allows_local_save` boolean to each video message and pass it from a new sender preference at send time. Receiving clients may still download for playback, but automatic received archives and explicit history saves are allowed only when the sender permitted local saving. The UI exposes the sender preference in Settings and disables received-message save actions when not permitted.

**Tech Stack:** Swift 6, SwiftUI/AppKit, XCTest, Supabase Postgres RPC migrations.

---

## File Structure

- Modify `Ping/Core/Models.swift`: add `VideoMessage.allowsLocalSave`, decode default `false`, and `canBeSavedLocally(by:)`.
- Modify `Ping/Capture/LocalArchive.swift`: add sender permission preference key and default migration.
- Modify `Ping/Backend/MessageService.swift`: include `allowsLocalSave` in `SendInput` and `ping_create_message` RPC body.
- Modify `Ping/AppDelegate.swift`: pass sender preference into send input; store received playback files only when both receiver auto-save and sender permission are true.
- Modify `Ping/UI/Setup/SettingsScene.swift`: rename received toggle copy and add sender-controlled save permission toggle.
- Modify `Ping/UI/History/HistoryViewModel.swift`: guard explicit save by `VideoMessage.canBeSavedLocally(by:)`.
- Modify `Ping/UI/History/MessageRowView.swift` and `Ping/UI/History/RoomTimelineView.swift`: pass `canSave` and only show the save action when true.
- Modify `Ping/UI/History/InlinePlayerView.swift` and `Ping/UI/History/VideoThumbnailView.swift`: avoid using received Documents archives for messages whose sender does not permit local saving.
- Modify `Ping/Backend/HistoryCacheService.swift`: keep history playback downloads in the application Caches directory instead of `Documents/Ping/cache`.
- Create `supabase/migrations/20260524000100_sender_local_save_permission.sql`: add column and recreate message RPCs with the flag in result sets.
- Modify `project.yml`: copy the new migration fixture for contract tests.
- Modify `PING_PROJECT_SPECIFICATION.md`: document sender-controlled local save behavior.
- Test files: `PingTests/VideoMessageCodingTests.swift`, `PingTests/LocalSavePermissionContractTests.swift`.

## Tasks

### Task 1: Plan And RED Tests

**Files:**
- Create: `docs/superpowers/plans/2026-05-24-sender-local-save-permission.md`
- Create: `PingTests/LocalSavePermissionContractTests.swift`
- Modify: `PingTests/VideoMessageCodingTests.swift`

- [ ] **Step 1: Write the plan document**

Save this plan to `docs/superpowers/plans/2026-05-24-sender-local-save-permission.md`.

- [ ] **Step 2: Add failing model tests**

Add tests that decode `allows_local_save`, default legacy payloads to `false`, and assert `canBeSavedLocally(by:)` returns true for the sender and for recipients only when allowed.

- [ ] **Step 3: Add failing contract tests**

Add string/resource contract tests that require:
- `LocalArchive.allowRecipientsToSaveMyVideosKey`
- Settings copy for sender-controlled permission
- `MessageService.SendInput.allowsLocalSave`
- RPC body key `allows_local_save_value`
- `HistoryViewModel.save` guard
- `MessageRowView.canSave`
- History playback cache under `.cachesDirectory`
- SQL migration resource containing `allows_local_save boolean not null default false`

- [ ] **Step 4: Verify RED**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/VideoMessageCodingTests -only-testing:PingTests/LocalSavePermissionContractTests
```

Expected: failure because the model property, helper, source strings, and migration fixture do not exist.

### Task 2: Message Model And Preference

**Files:**
- Modify: `Ping/Core/Models.swift`
- Modify: `Ping/Capture/LocalArchive.swift`

- [ ] **Step 1: Add `allowsLocalSave` to `VideoMessage`**

Decode `allows_local_save` with default `false`, add it to the memberwise initializer, and add:

```swift
func canBeSavedLocally(by uid: String?) -> Bool {
    if let uid, senderUid == uid {
        return true
    }
    return allowsLocalSave
}
```

- [ ] **Step 2: Add sender preference**

Add `allowRecipientsToSaveMyVideosKey = "ping.storage.allowRecipientsToSaveMyVideos"` and `allowRecipientsToSaveMyVideos`, defaulting to false in migration.

- [ ] **Step 3: Verify model tests**

Run the two focused test classes again. Expected: model/policy assertions pass; contract tests still fail on remaining implementation.

### Task 3: Send, Playback, And History Guards

**Files:**
- Modify: `Ping/Backend/MessageService.swift`
- Modify: `Ping/AppDelegate.swift`
- Modify: `Ping/UI/History/HistoryViewModel.swift`
- Modify: `Ping/UI/History/MessageRowView.swift`
- Modify: `Ping/UI/History/RoomTimelineView.swift`
- Modify: `Ping/UI/History/InlinePlayerView.swift`
- Modify: `Ping/UI/History/VideoThumbnailView.swift`

- [ ] **Step 1: Send the permission flag**

Add `allowsLocalSave` to `SendInput`, pass `LocalArchive.allowRecipientsToSaveMyVideos` from `AppDelegate`, and include `"allows_local_save_value": input.allowsLocalSave` in the RPC body.

- [ ] **Step 2: Respect the flag during received playback**

Use `LocalArchive.saveReceivedEnabled && message.allowsLocalSave` when choosing a received playback destination and when deciding whether to delete the file after playback.

- [ ] **Step 3: Respect the flag in history saves**

Have `HistoryViewModel.save` return an error message instead of copying when `message.canBeSavedLocally(by: currentUid)` is false.

- [ ] **Step 4: Hide save action when not allowed**

Pass `canSave: v.canBeSavedLocally(by: myUid)` into `MessageRowView` and show the context menu save button only when `canSave` is true.

- [ ] **Step 5: Avoid disallowed received archives as fallback**

In `InlinePlayerView` and `VideoThumbnailView`, return `nil` from `archivedVideoURL()` for received messages when `message.allowsLocalSave` is false.

- [ ] **Step 6: Move history playback cache out of Documents**

Use `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)` in `HistoryCacheService` so history playback downloads are cache files, not user-visible local archives.

### Task 4: Backend Migration And Docs

**Files:**
- Create: `supabase/migrations/20260524000100_sender_local_save_permission.sql`
- Modify: `project.yml`
- Modify: `PING_PROJECT_SPECIFICATION.md`

- [ ] **Step 1: Add Supabase migration**

Add `messages.allows_local_save boolean not null default false`, recreate `ping_create_message` with `allows_local_save_value boolean default false`, and include `allows_local_save` in `ping_incoming_messages`, `ping_get_message`, and `ping_room_messages` return sets.

- [ ] **Step 2: Copy migration fixture**

Add the new migration to the PingTests post-compile fixture copy script input and output lists.

- [ ] **Step 3: Update product spec**

Document that received video auto-save and explicit save are allowed only when the sender allowed local saving; clarify that playback may still use temporary/cloud cache.

### Task 5: GREEN Verification And Commit

**Files:** all modified files.

- [ ] **Step 1: Run focused tests**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/VideoMessageCodingTests -only-testing:PingTests/LocalSavePermissionContractTests
```

Expected: pass.

- [ ] **Step 2: Run full tests**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```

Expected: pass. If environment blocks GUI/unit tests, run a Debug build and report the blocker.

- [ ] **Step 3: Commit**

```bash
git add Ping PingTests supabase/migrations project.yml PING_PROJECT_SPECIFICATION.md docs/superpowers/plans/2026-05-24-sender-local-save-permission.md
git commit -m "feat(privacy): let senders control video saves"
```
