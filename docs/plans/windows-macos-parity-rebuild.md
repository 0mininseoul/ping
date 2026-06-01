# Windows macOS Parity Rebuild Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Rebuild the Windows client until it feels like the macOS Ping app: tray/background messenger lifecycle, reliable cross-platform rooms/messages, floating incoming video pings, polished capture/playback UI, and Windows-native installer/branding.

**Architecture:** Keep reusable Windows backend/capture code where it already matches macOS contracts, but treat the Windows shell and UX as a rebuild. Every Windows behavior must map to an explicit macOS reference state or protocol contract.

**Tech Stack:** WinUI 3 / Windows App SDK, C#/.NET, Supabase, Windows Shell tray/notifications, Windows Graphics Capture/camera/microphone, GitHub Actions Windows packaging.

---

## Non-negotiable parity gates

1. Closing the main window hides to tray; only explicit Quit exits.
2. Tray/background mode still receives notifications, hotkeys, and incoming pings.
3. App, taskbar, tray, start menu, installer, and alt-tab icons are Ping-branded.
4. Windows-sent text/video messages appear in macOS room timelines, and macOS-sent messages appear in Windows rooms.
5. Incoming video pings open a floating playback window/bubble like macOS.
6. Face/video surfaces are circular or soft-rounded, never raw rectangles.
7. Rooms look and behave like messenger conversations, not a debug utility.
8. Packaged EXE/MSIX runtime is tested before any public release/download update.

## PR order

1. `docs/windows-parity-spec` — macOS reference and protocol contract.
2. `fix/windows-shell-lifecycle` — tray/background/open/quit/icon foundation.
3. `fix/windows-message-protocol` — Supabase storage and message timeline compatibility.
4. `feat/windows-incoming-floating-playback` — realtime + notification activation route into floating playback.
5. `feat/windows-round-media-surfaces` — circular capture/playback controls using Windows-safe composition/custom control.
6. `feat/windows-room-chat-redesign` — messenger-style room list and mixed chat/video timeline.
7. `test/windows-packaged-smoke` — packaged install/launch/tray/mirror smoke tests.
8. `release/windows-parity-build` — artifact-only first, public release only after hardware QA sign-off.

## Foundation work started in this branch

- Restores tray `Open Ping` to the main shell instead of bypassing to history.
- Adds packaged Ping icon resource and uses it for app/tray/window branding.
- Hardens tray callback exceptions so Win32 message handling cannot crash the app.
- Uses Supabase authenticated storage download route for private video playback.

## Stop conditions

Do not spend time on visual room polish while any of these are still failing:

- Windows exits on main-window close.
- Windows cannot receive while hidden.
- Windows-sent messages do not appear in macOS room history.
- Incoming video pings do not open floating playback.
