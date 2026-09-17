# macOS APNs and Large Screen+Face Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move macOS video, chat, and invitation banners to APNs with presence-aware Mac/iPhone/Watch routing, keep auto face replies live-only, and open room-history screen+face videos in a 600-point floating player.

**Architecture:** Extend the existing Supabase device-token schema and Vercel APNs provider instead of adding a second backend. The Mac registers a production/development APNs token and keeps Realtime only for state and auto reply work; APNs is the only visible event-notification path. A focused AppKit window controller replaces the in-window screen+face overlay.

**Tech Stack:** Swift 6, AppKit, UserNotifications, Supabase Postgres/RLS/RPC/Database Webhooks, TypeScript/Vitest, Vercel Node Functions, APNs HTTP/2, XcodeGen.

---

### Task 1: Extend the device-token database contract

**Files:**
- Create: the exact `supabase/migrations/*_macos_apns_device_tokens.sql` path printed by `./scripts/supabase-ping.sh migration new macos_apns_device_tokens`
- Modify: `supabase/tests/device_tokens_test.sql`

- [ ] **Step 1: Create the migration through the guarded CLI**

Run `./scripts/supabase-ping.sh migration new macos_apns_device_tokens` and use the generated path. Do not invent the timestamp.

- [ ] **Step 2: Add failing pgTAP coverage**

Add assertions that `macos` and `sound_preference` are accepted, invalid platforms/sounds are rejected, and registering the same platform/token under a second authenticated UID transfers ownership rather than leaving two rows.

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

- [ ] **Step 3: Run the SQL tests and observe the failure**

Run the existing Supabase test command discovered with `./scripts/supabase-ping.sh test --help`, then the database test suite. Expected: failures because `macos`, `sound_preference`, and the four-argument RPC do not exist.

- [ ] **Step 4: Implement the migration**

Replace the platform check, add `sound_preference text not null default 'default'`, create a global unique index over `(platform, token)`, and replace the register RPC with this contract:

```sql
create or replace function public.ping_register_device_token(
    token_text text,
    platform_text text,
    environment_text text default 'production',
    sound_preference_text text default 'default'
) returns void
```

The security-definer body must call the existing authenticated-UID guard, validate every enum-like input, delete a conflicting `(platform, token)` row owned by another UID, and upsert the current UID. Revoke the obsolete three-argument overload before granting the four-argument function to `authenticated`.

- [ ] **Step 5: Verify locally and run database advisors when available**

Run the SQL suite, `./scripts/supabase-ping.sh migration list --local`, and the wrapper-supported advisor command discovered via `--help`. Expected: tests pass and no new security warnings.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations supabase/tests/device_tokens_test.sql
git commit -m "feat(push): support macOS APNs device tokens"
```

### Task 2: Implement platform-aware Vercel routing and invitation pushes

**Files:**
- Modify: `api/_lib/webhook.ts`
- Modify: `api/_lib/payload.ts`
- Create: `api/_lib/routing.ts`
- Modify: `api/push.ts`
- Modify: `api/_lib/__tests__/webhook.test.ts`
- Modify: `api/_lib/__tests__/payload.test.ts`
- Create: `api/_lib/__tests__/routing.test.ts`
- Modify: `api/_lib/__tests__/push.test.ts`

- [ ] **Step 1: Write failing parser, payload, and routing tests**

Cover an `invitations` INSERT and the exact target matrix:

```ts
expect(selectPushTokens(tokens, true).map(t => t.platform)).toEqual(['macos']);
expect(selectPushTokens(tokens, false).map(t => t.platform)).toEqual(['ios', 'watchos']);
expect(selectPushTokens([macToken], false)).toEqual([macToken]);
```

Also assert macOS payload categories/identifier keys, mobile video signed URLs, per-token sound omission for `none`, and per-platform APNs topics.

- [ ] **Step 2: Run focused Vitest files and observe failures**

Run `npm test -- --run api/_lib/__tests__/routing.test.ts api/_lib/__tests__/push.test.ts api/_lib/__tests__/webhook.test.ts api/_lib/__tests__/payload.test.ts`. Expected: missing invitation parser and routing exports.

- [ ] **Step 3: Add focused routing types and logic**

Define tokens with UID, platform, environment, and sound preference. Implement the approved exclusive routing contract in `routing.ts` without Supabase or APNs dependencies.

```ts
export type PushPlatform = 'macos' | 'ios' | 'watchos';
export function selectPushTokens(tokens: DeviceToken[], hasLiveMac: boolean): DeviceToken[]
```

- [ ] **Step 4: Add invitation parsing and platform payload builders**

Parse `id`, `to_uid`, `room_id`, `from_nickname`, and `room_name`. Build macOS categories compatible with `LocalNotificationCenter.Category`, while preserving the existing `PING_MESSAGE` mobile contract and signed video URL.

- [ ] **Step 5: Refactor `handlePush` around receiver batches**

Query `device_tokens` with `uid, token, platform, environment, sound_preference`. For each video receiver, chat room member, or invitation recipient, query live presence, select tokens, lazily mint a signed video URL only if a selected mobile token needs it, and call APNs with the topic returned by:

```ts
bundleIds: {
  macos: process.env.APNS_MACOS_BUNDLE_ID,
  ios: process.env.APNS_IOS_BUNDLE_ID,
  watchos: process.env.APNS_WATCHOS_BUNDLE_ID ?? process.env.APNS_IOS_BUNDLE_ID,
}
```

Keep secret validation, collapse IDs, 410 pruning, bounded logging, and 200 responses for recognized events with no eligible token.

- [ ] **Step 6: Run the full TypeScript suite**

Run `npm test`. Expected: all Vitest tests pass.

- [ ] **Step 7: Commit**

```bash
git add api
git commit -m "feat(push): route macOS mobile and invite notifications"
```

### Task 3: Register the Mac app with APNs and route remote actions

**Files:**
- Create: `Ping/Notifications/RemotePushRegistrar.swift`
- Modify: `Ping/AppDelegate.swift`
- Modify: `Ping/Notifications/LocalNotificationCenter.swift`
- Modify: `Ping/UI/Setup/SettingsScene.swift`
- Modify: `project.yml`
- Modify: `Ping.entitlements`
- Modify: `PingDebug.entitlements`
- Create: `PingTests/RemotePushContractTests.swift`

- [ ] **Step 1: Add failing Swift contract tests**

Assert the registrar calls `ping_register_device_token` with `macos`, the current APNs environment, and the current sound preference; `AppDelegate` forwards registration success/failure; remote payloads use the existing video/chat/invitation handlers; and project entitlements declare the macOS APNs environment without changing macOS 13 or Swift 6.

- [ ] **Step 2: Run the focused tests and observe failure**

Run `xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" -only-testing:PingTests/RemotePushContractTests test`. Expected: missing registrar source and callbacks.

- [ ] **Step 3: Implement `RemotePushRegistrar`**

Make it `@MainActor`, keep the current token in memory, call `NSApp.registerForRemoteNotifications()` after notification authorization, and retry backend registration after bootstrap/account changes/network recovery.

```swift
func update(deviceToken: Data)
func registerIfPossible(uid: String) async
func refreshSoundPreference(uid: String) async
```

Hex-encode the token, select `sandbox` for Debug and `production` for Release, and call `SupabaseClient.rpcVoid` with the four named SQL arguments.

- [ ] **Step 4: Wire AppDelegate callbacks and account lifecycle**

Implement `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` and the failure callback. Trigger registration after a successful bootstrap and after account switching. Do not persist the raw APNs token in UserDefaults or Keychain.

- [ ] **Step 5: Reuse the current notification delegate for remote payloads**

Normalize remote and local identifier keys in one parsing helper. Keep `willPresent([.banner, .sound])`, invitation actions, chat room focus, video playback, and Sparkle update actions.

- [ ] **Step 6: Regenerate the project and run tests**

Run `xcodegen generate`, the focused test, then the full macOS test suite. Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Ping project.yml Ping.entitlements PingDebug.entitlements PingTests/RemotePushContractTests.swift Ping.xcodeproj
git commit -m "feat(macos): register and handle APNs notifications"
```

### Task 4: Remove event-local banners while preserving live auto replies

**Files:**
- Modify: `Ping/AppDelegate.swift`
- Modify: `Ping/Notifications/LocalNotificationCenter.swift`
- Modify: `PingTests/AutoFaceReplyContractTests.swift`
- Create: `PingTests/PushOnlyNotificationContractTests.swift`

- [ ] **Step 1: Add failing tests for push-only event notifications**

Assert that invitation, chat, chat catch-up, and video observer paths do not call `UNUserNotificationCenter.add`. Assert that Sparkle update notification code remains and that video delivery still invokes `autoFaceReply.handleIncoming` before marking the row notified.

- [ ] **Step 2: Run focused tests and observe the current local calls**

Run the two focused test classes. Expected: failures identifying `notifyIncomingMessage`, `notifyIncomingChat`, `notifyChatCatchUp`, or `notifyIncomingInvitation` calls.

- [ ] **Step 3: Split event processing from notification presentation**

Remove the four user-event scheduling methods or make them unavailable to production paths. Invitation observers update state only. Chat Realtime refreshes history only. Video observers run live-only auto reply processing, mark the server row notified for polling deduplication, and may prefetch/autoplay according to the existing preference, but never create a banner.

- [ ] **Step 4: Guard auto replies against cold-start push handling**

Preserve `appStartTime` freshness checks and add an explicit source gate if necessary so notification-response fetches cannot enter the auto-reply coordinator.

- [ ] **Step 5: Run focused and full macOS tests**

Expected: event-local notification tests pass, automatic reply loop/freshness tests remain green, Sparkle tests remain green.

- [ ] **Step 6: Commit**

```bash
git add Ping/AppDelegate.swift Ping/Notifications/LocalNotificationCenter.swift PingTests
git commit -m "refactor(macos): use APNs as the only event banner path"
```

### Task 5: Add the 600-point floating screen+face history player

**Files:**
- Create: `Ping/UI/History/ScreenFacePlaybackWindow.swift`
- Modify: `Ping/UI/History/HistoryView.swift`
- Modify: `Ping/UI/Setup/RoomManagerWindow.swift`
- Modify: `Ping/UI/History/RoomTimelineView.swift`
- Modify: `Ping/UI/History/MessageRowView.swift`
- Delete: `Ping/UI/History/ScreenFaceExpansionOverlay.swift`
- Modify: `PingTests/RoomManagerUXContractTests.swift`

- [ ] **Step 1: Write failing sizing and lifecycle tests**

Test a pure sizing helper with a 600-point target, aspect-ratio clamp `0.5...3.0`, 32-point screen margins, and proportional downscaling. Contract tests must require a separate AppKit window, same-message toggle, room-change dismissal, Escape dismissal, and Enter replay.

```swift
XCTAssertEqual(ScreenFacePlaybackSizing.size(aspectRatio: 16.0 / 9.0, visibleFrame: largeFrame).width, 600)
```

- [ ] **Step 2: Run focused tests and observe failure**

Run `PingTests/RoomManagerUXContractTests`. Expected: no floating player type and the old 420-point overlay remains.

- [ ] **Step 3: Implement the focused window**

Create a borderless floating `NSWindow` with a 600-point content target, aspect-fit `AVPlayerLayer`, visible-frame clamping, room-window-centered placement, Escape close, and Enter replay. Keep loading/error behavior by resolving the cached/downloaded file before presentation or by hosting a focused SwiftUI loading view.

- [ ] **Step 4: Replace overlay state with window ownership**

The room manager/history root owns one playback window. Clicking a screen+face message opens or toggles it; selecting a different room and closing the parent closes it. Face-only messages remain inline. Remove the spacer/reporter workaround and obsolete overlay source.

- [ ] **Step 5: Run focused and full macOS tests**

Expected: 600-point sizing/lifecycle assertions pass and all existing history tests remain green.

- [ ] **Step 6: Commit**

```bash
git add Ping/UI/History Ping/UI/Setup/RoomManagerWindow.swift PingTests/RoomManagerUXContractTests.swift
git commit -m "feat(history): open screen recordings in a 600pt player"
```

### Task 6: Harden signing, release validation, and operational documentation

**Files:**
- Modify: `scripts/build-release.sh`
- Modify: `docs/PUSH_BACKEND_SETUP.md`
- Modify: `PING_PROJECT_SPECIFICATION.md`
- Modify: `README.md`
- Create: `PingTests/MacPushReleaseContractTests.swift`

- [ ] **Step 1: Add failing release contract tests**

Require the release script to accept an explicit provisioning-profile path, embed it as `Contents/embedded.provisionprofile`, inspect the final signed app entitlements, and reject any value other than production for `com.apple.developer.aps-environment`.

- [ ] **Step 2: Implement release checks**

Before the outer app signature, copy the validated profile. After signing, run:

```bash
codesign -d --entitlements :- "$APP" > "$TMP_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' "$TMP_ENTITLEMENTS"
```

Fail unless the value is `production`, the embedded profile exists, normal code-sign verification succeeds, and notarization remains unchanged.

- [ ] **Step 3: Synchronize product and operations documentation**

Update the product spec to APNs-only video/chat/invitation banners, exact routing, live-only auto reply, and 600-point floating playback. Update backend setup with `APNS_MACOS_BUNDLE_ID`, `APNS_IOS_BUNDLE_ID`, optional watch topic, the invitations webhook, and production smoke steps. Remove README claims that conflict with the new behavior.

- [ ] **Step 4: Run documentation and release contract tests**

Run the focused Swift tests and `git diff --check`. Expected: pass and no stale mandatory/offline auto-reply or local event-notification claims.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-release.sh docs/PUSH_BACKEND_SETUP.md PING_PROJECT_SPECIFICATION.md README.md PingTests/MacPushReleaseContractTests.swift
git commit -m "docs(push): document macOS APNs deployment"
```

### Task 7: Apply and verify the integrated system

**Files:**
- Modify only if verification exposes a defect in the files above.

- [ ] **Step 1: Run all local verification**

Run `npm test`, `swift test --package-path PingKit`, `xcodegen generate`, the full macOS `xcodebuild test`, and a Debug build. Expected: all pass.

- [ ] **Step 2: Apply the migration through the pinned wrapper**

Run `./scripts/supabase-ping.sh projects list`, verify ref `qxjtprxvjmaxlbtljcjw`, then run `./scripts/supabase-ping.sh db push`. Query the new constraint/function signature and run advisors. Stop rather than using a different project or raw access token.

- [ ] **Step 3: Update Vercel environment names and deploy**

Confirm the existing secrets without printing values, add the macOS/iOS topic variable names, deploy production, and verify `/api/health`, a bad-secret 401, and recognized no-token events. Keep the Hobby non-commercial constraint documented.

- [ ] **Step 4: Configure the invitations INSERT webhook**

Ensure `messages`, `chat_messages`, and `invitations` INSERT events reach the same endpoint with the shared secret. Do not alter UPDATE/DELETE behavior.

- [ ] **Step 5: Perform production APNs smoke tests**

Verify video/chat/invitation for: Mac live (Mac only), Mac quit plus mobile installed (mobile only), and Mac quit without mobile (Mac only). Verify push clicks, invitation actions, no event-local duplicates, live-only auto reply, and 600-point playback.

- [ ] **Step 6: Final status and commit**

Run `git status --short`, `git log --oneline -8`, and `git diff --check`. If verification fixes were needed, commit them with an appropriate scoped conventional commit. Report any external Apple provisioning or device matrix step that could not be completed, without claiming it passed.
