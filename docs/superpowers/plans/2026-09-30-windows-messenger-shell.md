# Windows Messenger Shell Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans, inline, then one whole-change reviewer. The user approved the parity strategy and explicitly requested continuous work until the complete product on 2026-09-30. Proceed through these tasks without renewed approval gates.

**Goal:** Make Ping's actual primary Windows window a usable messenger matching the current Mac room/timeline/composer intent, rather than a command/status dashboard.
**Architecture:** MainWindow owns application/tray lifetime and a reusable HistoryWindow UserControl. Keep HistoryViewModel services and transactional snapshots. Settings and room management remain owned secondary windows. UI metadata and composer policy are portable, with WinUI adapters and theme resources.
**Tech Stack:** Existing WinUI 3, .NET 10, native capture, xUnit.
**Spec:** docs/superpowers/specs/2026-09-30-windows-parity-design.ko.md sections 3–5, 7–9.

## Constraints and evidence

- Preserve platform/identity, anonymous account and production backend; no reset or backend migration.
- Reuse one actual main window for startup, tray, history hotkey and normal/notification activation. Closing hides to tray; explicit Quit disposes it.
- Theme resources must support light, dark, high contrast; no fixed width/height on messenger content. Minimum main size 760x540 DIP, starting size 1060x720 DIP.
- Room list uses name/member count/unread/default target; message rows use chronological date/time/sender and mine/peer alignment. No raw video IDs or separate reaction inspector.
- Context actions retain reply/save/removal/reaction permissions. Capture buttons route existing native commands.
- Composer Enter sends, Shift+Enter inserts line, IME composition Enter confirms rather than sends. Sending cannot erase a newer draft or a draft from another room. Per-room drafts/images are retained, in-flight send serialized; server failure retains text/image/reply.
- Connection errors are an inline banner and retry, do not replace or open another dashboard.
- UI verification must render the actual compiled WinUI surface with isolated test data; portable tests alone do not prove layout or window lifetime.

## Task 1 — Presentation and safe composer contracts

Files: HistoryRows.cs, HistoryViewModel.cs; new History/ComposerState.cs and tests; HistorySnapshot/HistoryViewModel tests.
- [x] Add failing cases for drafts across rooms, send failure/new typing/room switch, concurrent send, IME handling policy; message timestamp/day/ownership presentation.
- [x] Implement portable composer state and typed send outcome. UI bindings use per-room state, no blind clearing.
- [x] Verify complete App/Core suites; commit `feat(windows-chat): preserve drafts and composition while sending`.

## Task 2 — Actual single-window messenger

Files: MainWindow.xaml/.cs, App.xaml/.cs, Bootstrap/AppCoordinator.cs, History/HistoryWindow.xaml/.cs, theme dictionary.
- [x] Convert HistoryWindow to owned UserControl in MainWindow. Remove obsolete dashboard and route activation to one shell. Keep hiding and Quit semantics.
- [x] Apply Mac-reference spacing/surfaces, room details, unread badge, empty state, timeline metadata/context actions, compact composer, capture/room/settings controls, connection banner. Add automation labels/tab order.
- [x] Keep snapshots on UI thread, refresh selected conversation and rooms after connection, defer backend load until valid UID; suppress unintended selection callbacks during snapshot replacement.
- [x] Build WinUI/native; verify affected contracts; commit `feat(windows-ui): replace dashboard with unified messenger shell`.

## Task 3 — Actual WinUI rendering and interactions

Files: isolated local UI smoke runner plus build support, verification report.
- [x] Add explicit diagnostic build/run path that creates fixture RPC/storage, never reads user account/backend files or runs tray/camera. Render own WinUI content to PNG, check sizes/selection/draft/context actions/theme/lifetime. Avoid testing on production rooms.
- [x] Run and inspect real rendered light/dark snapshots and any runtime failures; fix identified defects and meaningful regression cases.
- [x] One independent review and correction, full tests/build/diff check; commit `test(windows-ui): verify compiled messenger shell and lifecycle`.

## Remaining full-product work

This milestone does not complete the active goal. Realtime/live playback/automatic replies, full account/device/settings parity, capture viewport, EXE/signing/update, and real device/Mac interoperability remain mandatory in the master design. After shell verification continue with the next milestone; keep the full goal active.
