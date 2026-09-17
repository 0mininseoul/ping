# macOS APNs Notifications and Large Screen+Face Playback Design

- Date: 2026-09-17
- Status: Approved for implementation
- Scope: macOS remote notifications, existing iPhone/Watch routing, live-only auto face replies, and room-history screen+face playback sizing

## 1. Goals

1. Deliver video, chat, and room-invitation notifications through APNs instead of macOS-scheduled local notifications.
2. Preserve notifications when the Mac app is not running, while keeping the existing iPhone/Watch companion behavior.
3. Run automatic face replies only when the Mac process was already running and received a fresh video event.
4. Replace the 420-point in-window screen+face expansion with a 600-point floating playback window that is wider than the default 500-point room window.

Sparkle update reminders remain local notifications because they originate on the device rather than from a Supabase event. Windows notification behavior is out of scope.

## 2. Routing Contract

Routing is exclusive for each receiver:

| Receiver state | APNs targets |
|---|---|
| At least one live Mac presence | macOS tokens only |
| No live Mac presence and iOS/watchOS tokens exist | iOS/watchOS tokens only |
| No live Mac presence and no iOS/watchOS tokens exist | macOS tokens only |

A live Mac presence is an unended `desktop_presence` row updated within the existing 45-second TTL. A registered macOS token remains available after the app quits so APNs can display the notification without the app process.

## 3. Architecture

The existing Supabase Database Webhook to the Vercel Hobby Node function `api/push.ts` remains the only push provider. It handles inserts from `messages`, `chat_messages`, and `invitations`, verifies the webhook secret, resolves recipients, reads presence and device tokens, selects target platforms using the routing contract, and sends APNs requests.

The existing APNs key is reused. The provider maps each platform to its own topic instead of using one global bundle ID. macOS uses `com.youngminpark.ping.Ping`; iOS/watchOS keep their existing topics and payload contract. APNs credentials, topics, the Supabase service-role key, and the webhook secret remain server-side Vercel environment variables.

The macOS app registers with APNs on every launch through `NSApplication.registerForRemoteNotifications()`. After Supabase bootstrap, the token is registered for the active anonymous account using `platform = macos`. Account switches transfer the token to the new UID so a device cannot continue receiving the previous account's notifications.

## 4. Database Contract

`device_tokens` accepts `macos` in addition to `ios` and `watchos`. A token belongs to one current UID. `ping_register_device_token` validates platform/environment, removes any stale ownership for the same platform/token, and upserts the authenticated UID. RLS continues to permit clients to read and remove only their own rows; the Vercel service-role client performs provider-side fan-out.

macOS tokens store the local sound preference (`default` or `none`). Re-registering after the preference changes updates this value. Mobile tokens retain the default sound behavior.

No service-role credential or APNs key is embedded in any client.

## 5. Notification Payloads and Actions

- Video: message ID, room ID, sender display name, and the existing video notification category.
- Chat: chat ID, room ID, sender display name, and a bounded preview.
- Invitation: invitation ID, room ID/name, inviter display name, and accept/reject actions.

macOS payloads contain identifiers and display metadata only. The authenticated client fetches authoritative data after a click. Existing iPhone video pushes continue to include the short-lived signed URL needed by the Notification Service Extension.

When the Mac app is active, `UNUserNotificationCenterDelegate.willPresent` displays the remote banner and sound. When the app is not running, macOS displays the alert directly. Clicking a cold-start notification routes through the same video, chat, or invitation handlers used today.

APNs collapse IDs use the event row ID. `410 Unregistered` tokens are removed. Other provider errors are logged without silently falling back to local notifications.

## 6. Local Processing and Auto Face Replies

Realtime and polling remain for room state, history refresh, and live auto face replies. They must not schedule local notifications for video, chat, or invitations.

For video events received while the process is running, the app applies the existing auto-reply safety policy. Messages created before the current app start, catch-up rows, automatic replies, stale messages, or camera-unavailable cases never trigger a reply. Receiving or clicking a remote notification must not launch an automatic reply by itself.

The client may still mark a video notification row as consumed for polling deduplication after processing the live/catch-up row, but APNs is the only user-visible banner source.

## 7. Signing and Distribution

The macOS App ID must have Push Notifications enabled. Debug builds use the development APNs environment and release builds use production. The Developer ID release contains the provisioning profile that grants `com.apple.developer.aps-environment` and remains Developer ID signed, hardened, notarized, and stapled.

The release script validates the embedded provisioning profile and production APNs entitlement before notarization. Missing or incorrect push signing fails the release rather than publishing an app that cannot register with APNs.

Vercel Hobby is acceptable because Ping is a non-commercial personal project and the expected invocation volume is within the included limits.

## 8. Screen+Face Playback

Clicking a screen+face video in a room opens a separate floating playback window rather than the existing 420-point SwiftUI overlay. The target content width is 600 points. Height is derived from the clamped stored aspect ratio. If a display cannot fit the target with 32-point margins, the window scales down proportionally to the visible frame.

The playback window is centered over the room window, then clamped to the active screen. It floats above the room without resizing the room or its sidebar. Clicking the same message again, selecting another room, closing the room window, or pressing Escape closes it. Enter restarts playback. Face-only circular inline playback is unchanged.

## 9. Failure Handling

- Notification permission denied: settings/onboarding shows the existing recovery route and APNs registration is retried after authorization.
- Token registration failure: log and retry on the next network recovery, account bootstrap, or app launch.
- Webhook/provider failure: log the failure; do not create a local notification fallback.
- Invalid/stale push payload: ignore safely and refresh room state when possible.
- Playback download failure: retain the existing inline error language in the floating window.

## 10. Acceptance Criteria

1. Video, chat, and invitation banners on macOS are delivered only by APNs.
2. With live Mac presence, only macOS tokens receive pushes.
3. With no live Mac presence and at least one mobile token, only iOS/watchOS tokens receive pushes.
4. With no live Mac presence and no mobile token, macOS tokens receive pushes while Ping is not running.
5. Existing iPhone/Watch payload behavior continues to work.
6. Automatic face replies occur only for fresh video events received by an already-running Mac app.
7. macOS account switching cannot leak notifications from the previous account.
8. Release validation rejects builds without the production macOS APNs entitlement and provisioning profile.
9. Room-history screen+face playback opens in a 600-point floating window, preserves aspect ratio, exceeds the default room-window width, and stays on screen.
10. Face-only playback and Sparkle local update reminders remain unchanged.

## 11. Verification

- TypeScript unit tests cover all three events, all three routing states, platform topics, sound metadata, signed-URL preservation, and token pruning.
- SQL tests cover macOS platform acceptance, token ownership transfer, validation, and RLS isolation.
- Swift tests cover APNs registration flow, payload action routing, removal of local event notifications, and live-only auto reply behavior.
- UI tests cover 600-point sizing, aspect-ratio preservation, visible-frame clamping, and dismissal/replay behavior.
- Manual production smoke tests cover video/chat/invitation with the Mac running, the Mac quit with mobile installed, and the Mac quit without mobile installed.
