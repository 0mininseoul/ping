# Ping APNs Push Backend Setup

This is the production runbook for Ping's macOS, iPhone, and Apple Watch push
notifications. The endpoint and database contract are already implemented in
`api/push.ts`, `api/_lib/`, and the Supabase migrations. Keep credentials in
Vercel or Apple services; do not commit them to this repository.

## Architecture

An INSERT in any user-event table is delivered through the Supabase Database
Webhook to the Vercel Hobby Node function, which looks up the recipient's
presence and device tokens and sends an APNs request:

```text
messages INSERT ─┐
chat_messages INSERT ─┼─> Supabase Database Webhook ─> /api/push ─> APNs
invitations INSERT ─┘
```

The same function handles `messages`, `chat_messages`, and `invitations`
INSERT events. There is no Supabase Edge Function and no local-notification
fallback for these events. Realtime and polling remain client-side paths for
room state, history refresh, and live-only automatic face replies.

## Supabase prerequisites

- Project ref: `qxjtprxvjmaxlbtljcjw` (`https://qxjtprxvjmaxlbtljcjw.supabase.co`).
- Apply migrations only through the guarded wrapper:

  ```bash
  ./scripts/supabase-ping.sh projects list
  ./scripts/supabase-ping.sh db push
  ```

- Authentication must allow Anonymous sign-ins.
- The `device_tokens` migration must be applied. It accepts `macos`, `ios`,
  and `watchos`, and stores the macOS sound preference.
- The `ping-videos` Storage bucket remains private.

## Vercel Production environment

Set these names in the `ping` Vercel project's **Production** environment.
Values are intentionally not documented here and must never be printed in
logs or committed to git.

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only token lookup and signed URL access |
| `PUSH_WEBHOOK_SECRET` | Shared secret checked against the webhook header |
| `APNS_KEY_ID` | Apple APNs Auth Key ID (not an App Store Connect API key) |
| `APNS_TEAM_ID` | Apple Developer Team ID |
| `APNS_P8` | APNs Auth Key `.p8` PEM contents |
| `APNS_MACOS_BUNDLE_ID` | `com.youngminpark.ping.Ping` |
| `APNS_IOS_BUNDLE_ID` | `com.youngminpark.ping.PingMobile` |
| `APNS_WATCHOS_BUNDLE_ID` | Optional watchOS APNs topic; when absent, the iOS topic is used |

The macOS and iOS topics are separate App IDs. Do not use a single legacy
topic for both platforms, and do not put the APNs key or service-role key in a
client bundle. Redeploy after changing environment variables; Vercel Hobby is
compatible with this non-commercial personal project and its expected volume.

## Database Webhooks

Create an HTTP `POST` webhook for each of these tables, all pointing to the
same endpoint:

| Table | Event | URL |
|---|---|---|
| `public.messages` | INSERT | `https://0minping.vercel.app/api/push` |
| `public.chat_messages` | INSERT | `https://0minping.vercel.app/api/push` |
| `public.invitations` | INSERT | `https://0minping.vercel.app/api/push` |

Use a five-second timeout and set the `x-webhook-secret` header to the same
value as `PUSH_WEBHOOK_SECRET`. Do not add UPDATE or DELETE events. If the
Dashboard names the hooks, use names such as `ping-push-messages`,
`ping-push-chat`, and `ping-push-invitations` so each table's delivery can be
audited independently.

## Routing contract

Routing is exclusive per recipient. A live Mac presence is an unended
`desktop_presence` row updated within the existing 45-second TTL. A registered
macOS token remains in `device_tokens` after the app quits so APNs can display
an alert while the Mac process is not running.

| Receiver state | APNs targets |
|---|---|
| At least one live Mac presence | macOS tokens only |
| No live Mac presence and iOS/watchOS tokens exist | iOS/watchOS tokens only |
| No live Mac presence and no iOS/watchOS tokens | macOS tokens only |

The third row is intentional: a Mac that is not running still receives the
push through APNs. Mobile video payloads retain their short-lived signed URL;
macOS payloads carry identifiers and display metadata, and the authenticated
Mac fetches authoritative data after the user clicks.

## macOS client and signing prerequisites

Enable Push Notifications on the macOS App ID `com.youngminpark.ping.Ping`.
Debug builds use the development APNs entitlement; Release builds must use
`com.apple.developer.aps-environment=production`. A Developer ID release also
needs the matching signed macOS provisioning profile embedded at
`Contents/embedded.provisionprofile`.

Supply the profile explicitly to the release script. The script validates the
signed profile, embeds the operator-provided file before the outer app
signature, inspects the final signed entitlements, then preserves the existing
codesign, notarization, stapling, and appcast flow:

```bash
./scripts/build-release.sh \
  --macos-provisioning-profile /secure/path/Ping-macOS.provisionprofile
```

The equivalent environment variable is
`PING_MACOS_PROVISIONING_PROFILE`. Never create, download, or check in a
profile or an Apple credential as part of this setup.

## Production smoke checks

Run these checks against production without printing secret values:

```bash
curl -sS https://0minping.vercel.app/api/health
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X POST https://0minping.vercel.app/api/push \
  -H 'x-webhook-secret: intentionally-wrong' \
  -H 'content-type: application/json' \
  -d '{}'
```

Expected results are `200` with `{"ok":true,"service":"ping-push"}` for
health and `401` for the wrong secret. A recognized INSERT whose recipient has
no eligible tokens should return `200` with `sent: 0`, not create a local
notification, and leave a bounded server log.

With real production tokens, test all three event types (video, chat, and
invitation) in each routing state:

1. Mac app running with fresh presence: only the macOS banner appears.
2. Mac quit with iPhone/Watch registered: only iOS/watchOS banners appear.
3. Mac quit with no mobile token: the macOS banner appears while the process is
   not running.

For every case, verify the click/action opens the correct room or playback,
invitation accept/reject actions work, there are no duplicate event-local
banners, and APNs 410 responses remove stale tokens. Separately verify that an
already-running Mac auto-replies only to a fresh live video event; a cold-start
push, polling catch-up row, or stale video never starts the camera. Verify a
screen+face history click opens the separate 600pt floating player and that
face-only playback remains circular.

## Failure handling and security

- Missing or invalid `APNS_MACOS_BUNDLE_ID` must fail the provider request
  rather than silently using the iOS topic.
- Provider failures are logged and returned for webhook retry; user-event
  notifications are not secretly re-created as local notifications.
- APNs keys, `SUPABASE_SERVICE_ROLE_KEY`, and `PUSH_WEBHOOK_SECRET` stay in
  Vercel's encrypted environment. Rotate a credential through its provider if
  it is exposed, and redeploy afterward.
