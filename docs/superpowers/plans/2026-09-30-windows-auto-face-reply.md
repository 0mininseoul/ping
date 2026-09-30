# Windows Auto Face Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, task-by-task, then one fresh whole-milestone reviewer. The existing full-parity approval and continuous completion request authorize execution without another design checkpoint.

**Goal:** Return a fresh three-second face clip to the original sender, with no reply loop, stale send, camera collision or focus theft.

**Architecture:** Core owns policy, exclusive camera leases and the cancellable reply pipeline. App adapters own MediaCapture, power/display signals and a nonactivating recording indicator. Reply upload uses the existing private Storage and authenticated RPC, with a final freshness/account check immediately before message creation.

**Tech Stack:** C#/.NET10, WinUI3, MediaCapture, existing native screen capture, Windows power notifications.

**Spec:** `docs/superpowers/specs/2026-09-30-windows-parity-design.ko.md`, sections5/9. Source references: `Ping/Core/AutoFaceReplyPolicy.swift`, `Ping/Capture/AutoFaceReplyCoordinator.swift`, `Ping/UI/Mirror/AutoReplyIndicatorWindow.swift`, `Ping/Backend/MessageService.swift`.

## Global Constraints

- Windows11 24H2+, x64/ARM64 targets retained; no Mac source/platform/version changes.
- Anonymous Auth, existing pinned project, private Storage; no remote schema/config/link or new authentication.
- Live only, created after process start, age0..60seconds, exactly3seconds face-only, original sender only, `is_auto_reply_value=true`.
- Incoming service coordinates are already Mac bottom-origin: reuse them in reply; never flip them again.
- Existing incoming/autoplay deduplication remains. Autoplay preference does not control automatic reply, matching Mac's independent path.
- User capture has priority; automatic capture cannot run while a manual camera lease is held. Sleep/display off cancels capture/upload and permanently abandons that attempt.
- No account tokens, QR or raw payloads in diagnostics. Fixture services and owned output only for tests.

## Review Focus

- A reply reaches a group: only the original sender receives it; no room-wide fanout.
- Camera initialization or upload finishes after sleep/account change: no late message is created.
- A manual mirror closes during initialization/recording: camera lease releases only after underlying camera work stops.
- Busy camera plus repeated delivery: no deferred surprise recording when camera becomes free.
- A nonactivating indicator appears at200% scale: existing foreground remains and indicator closes on all outcomes.

## Task1 — Policy, ownership and backend contract

Files: create `windows/src/Ping.Windows.Core/Capture/AutoFaceReplyPolicy.cs`, `CameraOwnership.cs`; modify `Backend/MessageService.cs`; tests `AutoFaceReplyPolicyTests.cs`, `CameraOwnershipTests.cs`, `AutoReplyContractTests.cs`.

Interfaces: `AutoFaceReplyPolicy.Decide(VideoMessage,string,IncomingArrivalSource,DateTimeOffset,DateTimeOffset,bool,bool,bool,bool)` returns typed skip reason or Record; `Recheck(VideoMessage,DateTimeOffset,bool)` rejects stale/interrupted work. `CameraOwnership.TryAcquire(CameraPurpose)` returns disposable lease; `AcquireManualAsync(CancellationToken)` cancels automatic owner and waits for disposal, returns null when another manual owner is active. Lease exposes cancellation token. `MessageService.SendAutoReplyAsync(AutoReplyVideoInput,Func<bool>,CancellationToken)` returns bool, rechecks permission after upload, deletes unused upload and creates exactly one RPC with face/flag/position.

- [x] Write RED tests for reply loops, duplicate/source/receiver/timestamp/expiry, freshness60 boundary, display/permission/busy and in-flight interruption.
- [x] Write RED lease tests for exclusivity, auto cancellation before manual grant, no grant before old cleanup, cancelled manual waiter and idempotent disposal.
- [x] Write RED fake RPC/storage tests for one sender, flag/face/ratio/position/save permission, no late create after upload, failure cleanup and rejected self/auto/mismatched receiver without upload.
- [x] Implement contracts; run full Core suite GREEN. Commit `feat(windows-auto-reply): enforce policy camera ownership and send contract`.

## Task2 — Owned cancellable reply pipeline

Files: create Core `Capture/AutoFaceReplyCoordinator.cs`, `CaptureActivityState.cs`; tests corresponding files.

Interfaces: coordinator injects clock/current identity/capability, record callback `(CameraLease,TimeSpan,CancellationToken)->Task<string>`, indicator `(VideoMessage,CancellationToken)->Task<IAsyncDisposable>`, send callback `(AutoReplyVideoInput,Func<bool>,CancellationToken)->Task<bool>`, temporary-file cleanup callback. `HandleIncoming` starts only an eligible nonqueued attempt and returns typed decision; `StopAsync` cancels/awaits owned work. State tracks display/suspend with monotonic interruption generation.

- [x] RED tests for3second record→original sender, duplicate/racing arrivals, busy skip without deferred capture, startup/reconnect/history exclusions, sleep during initialization/record/upload, old identity, stale post-record and failed capture cleanup.
- [x] Implement owned pipeline, independent from playback/download and notification success. Reserve eligible IDs per account before asynchronous work, including failed/interrupted attempts. Check before record and before create, always dispose indicator/lease and delete temporary clip.
- [x] Full Core/App suites GREEN. Commit `feat(windows-auto-reply): own cancellable fresh reply attempts`.

## Task3 — Native capture and runtime integration

Files: App `Capture/FaceRecorder.cs`, `OwnedScreenFaceCaptureEngine.cs`, `AutoReplyIndicatorWindow.cs`, `CaptureActivityAdapter.cs`; update both mirror windows, PermissionProbe, AppCoordinator; diagnostics fixture and App tests.

- [x] Integrate shared camera ownership with manual preview/record, native record and capability probes. Cancel/await camera initialization/record before release; release preview for native screen-face recording then restart on redo/idle. User requests interrupt automatic capture without stealing another manual lease.
- [x] Map power/display state and locked session to CaptureActivityState; stop attempts on account change/permanent recovery/quit. Check existing allowed camera/microphone capability without triggering auto permission prompts.
- [x] Show232x56DIP indicator,20DIP work-area margin, red recording state and sender; `AppWindow.Show(false)` and native noactivate/toolwindow style, no camera preview. Dismiss on every outcome. Wire live arrivals independently of auto-play preference and retain capture/reply dedupe.
- [x] Behavioral fake adapters and actual owned WinUI indicator fixture: geometry/current scale, nonactivation native styles, text, cleanup. Full suites/native/Release GREEN. Commit `feat(windows-auto-reply): integrate capture lifetime and recording indicator`.

## Task4 — Review and verification

- [ ] One fresh whole-milestone reviewer, fix verified important findings with RED/GREEN regression checks.
- [ ] Normal x64 Release/MSIX and diagnostic exclusion, fixture results; document real camera/power/backend/Mac/ARM64 limits separately. Commit `docs(windows): verify automatic face reply milestone`.
- [ ] Continue capture viewport/account/device/settings/EXE and real-device QA under the existing full goal; do not call this full product completion.
