# Apple Watch Push — Backend Setup (P1)

This records the live wiring for the Apple Watch push pipeline so P3/P6 can reproduce or audit it. Design: `docs/superpowers/specs/2026-05-29-applewatch-push-stt-design.md`. Plan: `docs/superpowers/plans/2026-05-29-applewatch-p1-backend-foundation.md`.

## Architecture (recap)

`messages` INSERT → Supabase Database Webhook → `https://0minping.vercel.app/api/push` (Vercel serverless) → looks up `device_tokens` for the receiver (service-role) → short-lived signed Storage URL → APNs (ES256 `.p8`, HTTP/2). No Supabase Edge Functions; free plan preserved.

## Supabase project

- Project ref: `qxjtprxvjmaxlbtljcjw` (URL `https://qxjtprxvjmaxlbtljcjw.supabase.co`).
- This repo is linked to that ref (`supabase link`). Apply schema changes with `npx supabase db push` (the DB password is stored in the OS keychain by `link`; a Personal Access Token is only needed for the initial link).
- Migration `20260529000100_device_tokens_and_push.sql` is applied and recorded in remote migration history. It is idempotent (`drop policy if exists` before each policy), so it is safe to re-run.

## Vercel environment variables (Project `ping`, Production)

Values are stored encrypted in Vercel — never in git. Names only:

| Var | Purpose |
|---|---|
| `SUPABASE_URL` | `https://qxjtprxvjmaxlbtljcjw.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | server-side DB access (RLS bypass) for token lookup + signed URLs |
| `PUSH_WEBHOOK_SECRET` | shared secret; must equal the webhook's `x-webhook-secret` header |
| `APNS_KEY_ID` | APNs Auth Key ID (`AZU5Y6PKU6`) — a **real APNs key** (developer.apple.com → Keys → APNs capability, Sandbox+Production). **NOT** the App Store Connect API key `TMC3PCHDCF`; using the ASC key here returns `403 InvalidProviderToken` on every send. |
| `APNS_TEAM_ID` | Apple Team ID (`878FAHTFQJ`) |
| `APNS_P8` | APNs Auth Key `.p8` contents (PKCS#8 PEM) for key `AZU5Y6PKU6` |
| `APNS_BUNDLE_ID` | `com.youngminpark.ping.PingMobile` (iOS app bundle id; set in P3). Needs a redeploy to take effect for real sends (P6). |

Env var changes require a redeploy to take effect (`vercel redeploy <prod-url>` or a git push).

## Supabase Database Webhook

- Database → Webhooks → `ping_push`
- Table `public.messages`, Events: **Insert** only
- HTTP Request, `POST`, URL `https://0minping.vercel.app/api/push`, timeout 5000ms
- Header `x-webhook-secret` = the `PUSH_WEBHOOK_SECRET` value

## Verified (P1)

Against production `0minping.vercel.app`:

- `GET /api/health` → `200 {"ok":true,"service":"ping-push"}`
- `POST /api/push` wrong secret → `401`
- `POST /api/push` non-INSERT event → `200 {"ignored":true}`
- `POST /api/push` valid INSERT, receiver with no tokens → `200 {"sent":0,"removed":0}` (confirms secret check, Supabase connect, `device_tokens` query, response path)

## Deferred to P3 / P6

- `APNS_BUNDLE_ID` (real iOS bundle id) + a registered device token → real APNs delivery to a device.
- End-to-end: a real ping INSERT firing the webhook → push landing on iPhone/Watch. (Not tested here to avoid spurious notifications on the live project.)

## Security note

The Personal Access Token and DB password used for the one-time `link`/`db push` were shared in a chat session. Rotate the PAT (https://supabase.com/dashboard/account/tokens) when convenient; future `db push` from this linked repo does not need it.
