# Windows Runtime Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the real Windows receiving coordinator with existing owned QA identities and verify notifications, automatic playback, tray lifetime, and shutdown while preserving the user's installed account.

**Architecture:** Keep production defaults. Supply explicit settings, mirror position, archive and notification directories to the existing injectable coordinator constructor. An opt-in diagnostic route boots one real receiver, with its own peer sending synthetic messages through the pinned backend. Stop the receiver before refreshing cleanup credentials and deleting only uniquely created QA data.

**Tech Stack:** .NET 10, WinUI 3, Windows App SDK 2.1.3, existing Supabase REST/RPC and Realtime wrappers.

**Spec:** `docs/windows/2026-09-30-repository-audit.ko.md`, `PING_PROJECT_SPECIFICATION.md`, current `Ping/` reference and user Windows parity goal.

## Global Constraints

- Preserve macOS 13+, Swift 6+, `.pingGlassEffect()` wrapper and existing Mac startup implementation; no Mac source changes.
- Preserve `YoungminPark.PingWindows`, Publisher `CN=Youngmin Park`, current profile and session paths in ordinary runs.
- Pinned backend `qxjtprxvjmaxlbtljcjw`; anonymous identities only; private storage; no SQL, project or account-link changes.
- User-authorized Windows typography uses packaged Pretendard Variable. Test windows are on DISPLAY3.
- Existing A/B QA sessions must be valid and distinct before network operations; never create replacement accounts in diagnostics.
- Native diagnostic types are excluded from normal Release packages. No token, key, QR or response-body output.

## Review Focus

- Receiver startup writes settings or notification ledgers outside its owned runtime root.
- Startup/catch-up videos unexpectedly autoplay or trigger camera capture.
- Replay or repeated polling duplicates a toast, player, seen update or remote acknowledgement.
- Receiver shutdown races cleanup and writes a stale refresh token.
- A failed enumeration or media delete destroys the only repair record or leaves unknown private media.

## Task 1: Runtime storage scope

**Files:** create `windows/src/Ping.Windows.App/Bootstrap/AppCoordinatorStorage.cs`; modify `AppCoordinator.cs`.

- [x] Introduce explicit directory/path options for the existing injectable constructor; ordinary constructor retains exact default locations.
- [x] Pass the notification directory to `NotificationController.UseAccount`; use owned settings, placement and archive stores.
- [x] Build the actual native app. Verify owned runtime files and original profile snapshots in Task 2 rather than tests that mirror path construction.

## Task 2: Real receiving runtime

**Files:** create `Diagnostics/OwnedRuntimeSmoke.cs`; modify `Program.cs`, `UiSmokeRunner.cs`, owned live launch script.

- [x] Explicit opt-in route restores existing QA sessions and requires empty QA room lists.
- [x] Create one unique two-person room. Boot receiver AppCoordinator with scoped stores and actual tray/hotkey/notification services. Both message modes use owned three-second files, never hardware capture.
- [ ] Confirm receiving room/chat, actual OS notification queue, automatic player decoding/seen, duplicate suppression and replay. Notification routing may be invoked through its public app handler; distinguish this from a literal shell toast click.
- [x] Close messenger through its native window and verify the same HWND survives hidden. Reopen using the coordinator entry point. Do not inject input into unrelated apps.
- [x] Stop receiver fully, load current cleanup session, remove owned rows/objects, leave both memberships, read back empty lists and original user-file hashes.
- [x] Record unsupported real OS notification behavior as a limitation, not a simulated pass.
- [x] Request one read-only review, fix important findings, run appropriate native/portable checks and commit the coherent deliverable.

## Full goal remains

0.4.10 is installed and its EXE/MSIX, typography, focused conversation and owned native/server messaging are verified. This plan does not replace remaining requirements: actual camera/microphone recording, Mac↔Windows feature matrix, ARM64 device, DPI/high-contrast visual comparison, update failure/recovery and original complete UI input validation. No hardware absence blocks the runtime work above.

## Progress ledger

Task 1 native storage scoping verified with actual receiver and original-profile snapshots. Task 2 diagnostic implementation and read-only review completed; OS notifications and automatic playback are still unverified because unpackaged registration returned 0x8007007E. Public activation handler playback is recorded separately, not substituted as automatic-playback evidence. Results: [runtime report](../../windows/2026-10-05-windows-runtime-readiness.ko.md). No full goal completion claim.
