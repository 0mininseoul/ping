# Windows Connection Foundation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the current session, task-by-task. Steps use checkbox syntax. The user explicitly requested implementation of the approved strategy on 2026-09-30; continue within that authorization.

**Goal:** Preserve the Windows user's anonymous account and conversations across network failures, reconnect automatically, and enforce current read/delete permissions.
**Architecture:** Keep the existing Core services and native capture. Introduce structured HTTP errors, a file session store, a portable connection supervisor, and transactional timeline snapshots; adapt the existing coordinator and history window to those contracts.
**Tech Stack:** C#/.NET 10, WinUI 3, Windows App SDK 2.1.3, existing native C++ capture, xUnit.
**Spec:** `docs/superpowers/specs/2026-09-30-windows-parity-design.ko.md`, first implementation scope in section 6.

## Global Constraints

- Windows 11 24H2+, x64/ARM64; preserve package identity and existing backend.
- Preserve `%LOCALAPPDATA%\Ping\SupabaseSession.json`; no silent account reset, no secrets in logs.
- Keep original RPC named arguments, private storage and anonymous auth.
- Retry delays 1/2/5/10/30/60 seconds, max 60, jitter and Retry-After.
- Sender deletion window five minutes; receiver hide requires matching receiver.
- No macOS source change or production DB operation required by this plan.

## Review Focus

- Invalid/empty session JSON must not call anonymous signup.
- Canceled token refresh must preserve persisted tokens and propagate cancellation.
- Overlapping reconnection triggers must not create parallel bootstrap or duplicate observers.
- Late response for room A must not overwrite room B or mark A read.
- A group-member video not addressed to this account must not expose receiver-hide.

## Task 1: Reproduce baseline and fix authentication/session persistence

**Files:** Create `windows/src/Ping.Windows.Core/Backend/SupabaseRequestException.cs`, `SupabaseSessionStore.cs`; modify `SupabaseClient.cs`; tests `windows/tests/Ping.Windows.Core.Tests/SessionRecoveryTests.cs`, existing `BackendContractTests.cs`.
**Interfaces:** `SupabaseRequestException : HttpRequestException` exposes `ErrorCode`, `RetryAfter`, `IsSessionRejected`; `SupabaseSessionStore(string path).LoadAsync(CancellationToken)` / `SaveAsync(SupabaseSession, CancellationToken)`; `SupabaseSessionReadException` preserves the underlying reason.

- [x] Install local .NET 10, run both existing test projects; prepare Windows SDK 26100+ without changing app target. Record baseline and any native build prerequisites.
- [x] Add failing tests: 408/429/500/503 and transport failure preserve identity and remain retryable; explicit `refresh_token_not_found` / `refresh_token_already_used` rejects; cancellation propagates; damaged/null/missing-field JSON never signs up; original saved file survives failed/canceled writes; a successful second write creates a valid previous backup.
- [x] Run `dotnet test windows/tests/Ping.Windows.Core.Tests --filter SessionRecoveryTests`; verify behavioral failures.
- [x] Implement structured response classification, validate session data, atomic temp write/replace, safe backup behavior; keep expired exception only for explicit permanent denial. Change the old corrupt-session fallback test to assert preservation.
- [x] Run complete Core tests. Commit `fix(windows-auth): preserve sessions across transient failures`.

## Task 2: Connection supervisor and Windows lifecycle adapter

**Files:** Create Core `Backend/ConnectionSupervisor.cs`, App `Bootstrap/ConnectionLifecycleAdapter.cs`; modify `Bootstrap/AppCoordinator.cs`; test Core `ConnectionSupervisorTests.cs`.
**Interfaces:** `ConnectionSupervisor(Func<CancellationToken, Task> connectAsync, ... injected delay/jitter).Start()`, `RequestReconnect()`, `StopAsync()`, `StateChanged`; states `Connecting`, `Connected`, `Retrying`, `SessionRejected`, `ConfigurationRequired`, `Stopped`. Adapter owns network/power handlers.

- [x] Write behavioral tests for offline→success, delay progression/cap/Retry-After, immediate wake, permanent rejection stop, disposal cancel, many triggers→one bootstrap.
- [x] Run focused tests and observe expected failures.
- [x] Implement supervised bootstrap, retained room/profile state, network/resume wake signals. Avoid restarting existing incoming loops when already running. Marshal UI changes through DispatcherQueue.
- [x] Run complete Core/App tests and compile App where available. Commit `fix(windows): recover connections without replacing identity`.

## Task 3: Transactional history snapshots and visible-room read policy

**Files:** Modify App `History/HistoryViewModel.cs`, `HistoryWindow.xaml.cs`, `Bootstrap/AppCoordinator.cs`; tests `HistoryViewModelTests.cs`, new `RoomVisibilityPolicyTests.cs` if policy is extracted.
**Interfaces:** Inject `Func<string, bool> canMarkRoomRead` into HistoryViewModel (default safe policy) and expose `MarkVisibleRoomReadAsync(CancellationToken)`; load generation checks guard snapshot apply. Window visibility provider observes actual activation and HWND foreground.

- [x] Add failures for old timeline preserved on RPC failure, deferred A response after B selection, selected row/reply retained, hidden/background no read RPC, foreground read exactly for selected room.
- [x] Run focused History tests; confirm failures.
- [x] Fetch video/chat concurrently into local snapshot, apply only current room generation; optional attachment failures do not discard text. Share visible/foreground checks for read and notification cleanup.
- [x] Run full App tests plus build. Commit `fix(windows-history): preserve conversations and foreground read state`.

## Task 4: Current message model and deletion permissions

**Files:** Core `Models/VideoMessage.cs`, new `Models/MessageRemovalPolicy.cs`, `Backend/MessageService.cs`; App `History/HistoryRows.cs`, `HistoryViewModel.cs`, `HistoryWindow.xaml`; tests Core/App removal tests and affected backend fixtures.
**Interfaces:** decode `is_auto_reply`; `MessageRemovalPolicy` returns none/delete/hide given sender, receiver, timestamp, current UID and injected time. `MessageService.RemoveAsync(string, CancellationToken)` interprets RPC missing/deleted/hidden.

- [x] Test auto reply payload, exact five-minute boundary, future/missing timestamps fail closed, sender/receiver/third party, server rejection retains rows.
- [x] Observe failing focused tests, implement UI permissions and server result handling, refresh expiry while room is open.
- [x] Run complete Core/App suites. Commit `fix(windows): align message permissions with current backend`.

## Task 5: Build and verify foundation

**Files:** Update this plan progress, `docs/windows/2026-09-30-foundation-verification.ko.md`; build support scripts only if an actual portability defect is found.

- [x] Run full tests, `git diff --check`, x64 managed/native App build with required SDK. Record exact commands and results.
- [ ] Run packaged foundation smoke when signing/config is available; never describe portable tests as packaged runtime verification.
- [x] Dispatch one independent whole-branch review as required by executing-plans; resolve material findings with failing tests first.
- [x] Record remaining hardware/signing/SDK limitations and subsequent parity tasks. Commit `docs(windows): record connection foundation verification`.

## Remaining program

This plan implements section 6 of the approved design. Incoming live/floating playback, shell redesign, capture viewport, account/device settings, auto reply, Windows remote push and release EXE remain tracked in the design and audit. Completing this plan alone is not full Windows/macOS parity.
