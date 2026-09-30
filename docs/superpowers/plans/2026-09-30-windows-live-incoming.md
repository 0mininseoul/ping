# Windows Live Incoming Implementation Plan

> Execute inline with superpowers:executing-plans; one independent whole-change review at the end. The approved Windows parity strategy and continuous full-product request authorize this milestone. Keep the full goal active after it; account/capture/settings/EXE milestones remain.

**Goal:** Deliver incoming chats/videos promptly, recover subscriptions without stale tokens or duplicate side effects, and display received videos through the same native playback path as notifications/history.

**Architecture:** Core owns typed arrival sources, policy, account-scoped delivery reservations and a testable Realtime transport/session. App owns observers, notifications, serialized playback preparation and WinUI placement. Realtime changes are invalidation signals; existing authenticated RPCs remain authoritative. Preserve existing deduplication while consolidating incoming ownership.

**References:** master Windows parity design sections 3–5; Ping/Backend/ChatRealtimeService.swift; Ping/AppDelegate.swift delivery/prefetch/group paths; Ping/Core/UserPreferences.swift; Ping/UI/Playback/PlaybackGroupLayout.swift and history ScreenFacePlaybackWindow.swift.

**Verified external contracts:** [Supabase protocol](https://supabase.com/docs/guides/realtime/protocol), v1 JSON object frames explicitly selected; fresh `access_token` pushes; `phx_join`/reply/heartbeat handling. Changelog reviewed 2026-09-30, including realtime-schema lock down: this milestone does not modify that schema or remote project configuration.

## Task 1 — Arrival policy and shared delivery ownership

- [x] RED/GREEN tests for live/startup/reconnect/click, missing/future timestamps, expiry, wrong receiver, preference off and 60-second autoplay freshness boundary. Notification-click replay remains explicit and is not suppressed by autoplay ledger.
- [x] Account-scoped bounded delivered/in-flight IDs, concurrent reservation, release on failure, commit after side effects. No tokens/body/QR in persistence or diagnostics. Keep startup catch-up notifications distinct from autoplay.
- [x] Full Core tests; commit `feat(windows-incoming): distinguish live arrivals and catch-up`.

## Task 2 — Recoverable authenticated Realtime

- [x] Expose minimal current configuration/token access through SupabaseClient without logging secrets or bypassing its authentication lock.
- [x] Injectable WebSocket transport plus v1 protocol decoder, receive fragmentation/size limit, serialized sends, join success/timeout/failure, heartbeat acknowledgement timeout, latest token renewal, cancellation/disposal, bounded backoff. Subscribe chat/reaction room filters and incoming receiver filter; DELETE payloads lacking room metadata trigger safe refresh.
- [x] Fake transport tests for dropped socket, invalid frames, subscription rejection, token change, repeated start/room replacement, in-flight shutdown. No operational backend used by tests.
- [x] Full tests and WinUI build; commit `feat(windows-realtime): recover authenticated subscriptions`.

## Task 3 — Actual incoming and playback integration

- [x] One owned observer connects Realtime invalidations and fallback polling through shared delivery coordinator; coalesce fetches, distinguish startup/reconnect batches, preserve periodic reconciliation, stop old tasks on termination/account change. Polling must not concurrently duplicate an event-driven fetch or notification.
- [x] Refresh room unread metadata/visible timeline and handle deletes/reactions; do not mark hidden rooms read. Notification delivery failures remain retryable. Server notified acknowledgement follows successful local delivery, without blocking later playback preparation.
- [x] Add persisted auto-play preference (default on), route automatic/notification/history replay through shared playback ownership/cache. Bound preparation concurrency, deduplicate pending windows, cancel lifetime work and isolate an item failure.
- [x] Native face200-DIP circle, screen history600-DIP target with32-DIP margins/aspect fit, sender position/DPI/display clamping, ended/replay/escape/10-second dismissal. Group auto-reply playback windows without overlap. Face thumbnails are circular; capture-specific sizes remain separate.
- [x] Real owned WinUI fixture tests for playback geometry/lifecycle and preference controls; mock delivery/read/notification/preparation flows. Full tests/build; commit `feat(windows-playback): present live pings through shared delivery`.

## Task 4 — Review and verification

- [ ] Independent review; correct verified important findings with regression checks. Verify normal Release/native/MSIX and fixture exclusion. Record what was tested and hardware/real backend limits.
- [ ] Commit verification report, continue to automatic reply/capture, account/device/settings and final installer milestones. Never equate simulated delivery or unsigned MSIX with real Mac interoperability or EXE install success.

## Authorization and limits

No new Supabase project, no service-role credentials, no new login/remote link, no remote schema migration in this plan. Use current public anon configuration and current user session only at runtime. Missing local configuration/signing material limits real-device release QA but does not prevent implementing/testing these subsystems. Explicit remote credential/link requirements from AGENTS.md still apply if that work becomes necessary.
