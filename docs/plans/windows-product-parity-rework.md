# Windows Ping Product Parity Rework Plan

> **For Hermes / future implementer:** Do not treat this as a cosmetic XAML pass. The goal is to make Windows Ping feel like the same messenger product as macOS. Existing PR37-style card restyling is considered a failed approach.

**Goal:** Rebuild Windows Ping so the user can QA only details, not reject the whole product direction.

**Architecture:** Split the work into product-critical slices: (1) reject/rollback failed History restyle, (2) fix launch/single-instance/window lifecycle, (3) rebuild room/chat UI as a messenger shell, (4) fix installer trust/progress UX, (5) verify with screenshots and real Windows artifacts. Each PR must include visual evidence and acceptance-gate notes.

**Tech Stack:** WinUI 3 / C# / XAML, Windows App SDK packaged app, Inno Setup + PowerShell installer, GitHub Actions artifacts, Supabase-backed room/message data.

---

## Non-negotiable Product Intent

Windows Ping must be a messenger utility, not a debug/control panel.

A passing Windows build should feel like:

- KakaoTalk/Slack/Discord-style background messenger utility.
- Mac Ping's Windows sibling, not a separate broken EXE.
- Rooms are the primary surface.
- Chat/video pings are visible as a conversation timeline.
- The app can live in tray/background and receive/play incoming pings.
- Installer feels transparent and trustworthy.

A failing build looks like:

- Big empty black window with a small status card.
- `History`, `Refresh`, `Play selected video`, `Ping is ready`, `Windows tray and hotkeys` as primary UI.
- Reaction buttons dominating the message UI.
- Form/admin/debug panel instead of messenger room.
- Hidden downloader with mismatched progress.
- Start menu click opening multiple History windows.

---

## My Quality Bar / Kill Criteria

Do not ship or ask the user to QA if any of these are true:

1. **No screenshot evidence:** PR has no Windows screenshots for home/rooms/timeline/composer/installer.
2. **No real artifact:** only source/tests changed, no Windows artifact build checked.
3. **Still looks like a panel:** if the main view can be described as a settings/status panel, fail.
4. **History window duplicate:** start menu, tray, hotkey, notification, or History button opens more than one History/Rooms window.
5. **Utility buttons primary:** `Refresh` / `Play selected video` are prominent primary actions in the room UI.
6. **No timestamps/status:** messages/video cards do not show sender, time/status, and clear play affordance.
7. **Installer opaque:** thin downloader hides what it downloads or shows inaccurate progress.
8. **Home has huge empty gutters:** content is centered in a tiny column inside a huge window with black side voids.
9. **String tests only:** tests only assert XAML contains words/radii without behavioral/source contracts.
10. **No macOS comparison:** no state-by-state macOS reference or explicit intentional difference list.

If any kill criterion triggers, stop and revise before giving the user a build.

---

## Target UX Spec

### A. Main Shell

Primary purpose: show rooms/recent activity, not hotkey status.

Required structure:

- Compact messenger window size, no giant black side voids.
- Left: room/conversation list.
- Right or main body: selected room preview/timeline, or helpful empty state.
- Bottom/status: tray/background state can be subtle, not page headline.
- Primary CTA: New Face Ping / Screen+Face Ping should be accessible but not make the app look like a debug launcher.
- Settings/hotkeys go secondary.

Forbidden as primary UI:

- `Windows tray and hotkeys` subtitle as product headline.
- `Ping is ready` card as the main content.
- `Rooms and recent pings` empty admin card without actual conversations.

### B. Rooms / Chat UI

Primary purpose: a real messenger room.

Required structure:

- Left conversation list:
  - room avatar/initial
  - room name
  - last message/video summary
  - last activity time
  - unread/new marker if available
  - selected state subtle, not Windows default blue slab

- Room header:
  - room name
  - participants / status summary
  - secondary actions tucked right: refresh, settings, maybe overflow menu

- Timeline:
  - chat bubbles, not full-width cards for every message
  - sender name when needed
  - timestamp/status
  - incoming/outgoing visual alignment if current-user identity is known
  - video ping bubble with thumbnail/preview, circular/rounded play affordance, capture type label
  - reactions as small inline chips, not huge button rows
  - reply preview integrated inside bubble

- Composer:
  - bottom fixed input bar
  - placeholder like `Message {room}`
  - attach button small icon/button
  - send button integrated and obvious
  - Enter sends, Shift+Enter newline

Forbidden:

- Timeline title saying `Live room timeline — text, reactions, and video pings`.
- Large `Reply` button under every chat message.
- Huge row of six reaction buttons repeated under every message.
- `Play selected video` as a top-level workflow.
- Raw IDs visible in UI.

### C. Incoming Playback / Background

Required:

- X close hides to tray, explicit Quit exits.
- Start menu/shortcut activation focuses existing app, does not spawn duplicate windows.
- Incoming video opens floating playback bubble/window like macOS.
- If main window is open, incoming playback still uses deterministic behavior.
- Notifications click through to the same single app instance.

### D. Installer

Preferred direction: self-contained EXE. If impossible short-term, thin downloader must be transparent.

Required for thin downloader:

- Display current operation: certificate, package, dependency manifest, dependency package, install.
- Display current filename and source domain.
- Real progress for download bytes where possible.
- Inno progress must not imply unrelated completion.
- Launch-after-install default should not surprise users with a big home/status window; either default off or launch minimized/tray with clear checkbox copy.

Forbidden:

- Hidden PowerShell downloads with only generic Inno progress.
- Mismatched progress bar that completes while download still continues.
- No indication of downloaded files.

---

## Required PR Breakdown

### PR 1: Reset bad History restyle and write visual contract

**Objective:** Prevent another shallow card-restyle pass.

**Files:**
- Modify/revert as needed: `windows/src/Ping.Windows.App/History/HistoryWindow.xaml`
- Create/modify: `docs/parity/windows-room-ui-contract.md`
- Modify tests: `windows/tests/Ping.Windows.App.Tests/AppCoordinatorSourceTests.cs`

**Steps:**
1. Compare current branch against `origin/main` and identify PR37-only UI restyle changes.
2. Either revert failed cosmetic changes or replace with a minimal neutral baseline before rebuilding.
3. Write `docs/parity/windows-room-ui-contract.md` with this plan's Target UX Spec.
4. Add source-contract tests that fail if primary forbidden labels are prominent:
   - `Play selected video` not top-level primary button.
   - `Live room timeline — text, reactions, and video pings` absent.
   - raw `VideoId` not displayed.
5. Run Windows app tests.
6. Commit.

**Verification:**
- `git diff --stat origin/main...HEAD` shows intentional reset/spec/test work only.
- Tests fail before removing forbidden labels and pass after.

---

### PR 2: Fix single-instance and duplicate History windows

**Objective:** Start menu, shortcut, tray, hotkey, notification cannot open duplicate History/Rooms windows.

**Files:**
- Modify: `windows/src/Ping.Windows.App/Program.cs`
- Modify: `windows/src/Ping.Windows.App/App.xaml.cs`
- Modify: `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- Modify/add tests: `windows/tests/Ping.Windows.App.Tests/*`

**Steps:**
1. Trace activation sources: start menu shortcut, AppsFolder launch, notification, hotkey, tray menu.
2. Add a single `OpenOrFocusRoomsAsync` / `OpenOrFocusHistoryAsync` gate in `AppCoordinator`.
3. Ensure all activation paths call the same method.
4. Add a reentrancy guard around History window creation (`SemaphoreSlim` or UI-thread boolean) so two near-simultaneous activations cannot both create windows.
5. On redirected activation, show/focus shell or target room but never instantiate a second coordinator/window.
6. Add source tests that all History open paths use the single gate.
7. Manual Windows QA: click Start menu icon twice rapidly; only one Rooms/History window remains.
8. Commit.

**Verification:**
- Start menu click x2 -> one window.
- History button x2 -> one window.
- Hotkey + Start menu race -> one window.
- Notification click while app running -> same process/window.

---

### PR 3: Rebuild main shell as messenger home

**Objective:** Remove the big debug/status home and make rooms/recent activity the first-class screen.

**Files:**
- Modify: `windows/src/Ping.Windows.App/MainWindow.xaml`
- Modify: `windows/src/Ping.Windows.App/MainWindow.xaml.cs`
- Modify: `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- Possibly create: `windows/src/Ping.Windows.App/Rooms/*`
- Tests: `windows/tests/Ping.Windows.App.Tests/*`

**Steps:**
1. Remove giant black gutters by sizing shell content to a compact messenger window or responsive layout.
2. Replace `Ping is ready` status card with actual rooms/recent activity list.
3. Move hotkey/tray text to a subtle footer/settings area.
4. Make primary actions compact and messenger-appropriate.
5. Add empty state: friendly, product-facing, not diagnostic.
6. Add tests preventing `Windows tray and hotkeys` and `Ping is ready` from being the main content.
7. Build artifact.
8. Capture screenshot.
9. Commit.

**Verification:**
- Screenshot passes: no massive empty gutters; rooms are visually primary.
- User should immediately understand where conversations live.

---

### PR 4: Rebuild Rooms/Timeline UI as real messenger

**Objective:** #35 passes visually and behaviorally.

**Files:**
- Modify or replace: `windows/src/Ping.Windows.App/History/HistoryWindow.xaml`
- Modify: `windows/src/Ping.Windows.App/History/HistoryWindow.xaml.cs`
- Modify: `windows/src/Ping.Windows.App/History/HistoryViewModel.cs`
- Modify: `windows/src/Ping.Windows.App/History/HistoryRows.cs`
- Tests: `windows/tests/Ping.Windows.App.Tests/*`

**Steps:**
1. Rename product mental model from History to Rooms where user-facing.
2. Left list: room avatar, name, last message summary, time, selected state.
3. Header: room name + participants/status + secondary actions.
4. Timeline: chat bubble component for text messages.
5. Timeline: video bubble component with thumbnail/play/capture type/time/sender.
6. Reactions: convert from repeated huge buttons to small inline chips and a compact add-reaction affordance.
7. Reply: reply preview inside bubble/composer, not big `Reply` button under every message.
8. Composer: fixed bottom bar with attach/send integrated.
9. Hide developer controls behind secondary menu or keyboard shortcuts.
10. Add tests for forbidden UI strings and required messenger tokens.
11. Build artifact.
12. Capture screenshots for: empty room, populated room, video message, chat composer.
13. Commit.

**Verification:**
- Looks like messenger room at first glance.
- User should not need explanation to send a message/video.
- #35 acceptance criteria checked one by one in PR body.

---

### PR 5: Installer transparency / self-contained decision

**Objective:** Installer must not feel sneaky or regress from previous user expectations.

**Files:**
- Modify: `windows/installer/PingSetup.iss`
- Modify: `windows/scripts/install-ping-windows.ps1`
- Modify: `windows/scripts/build-installer.ps1`
- Modify release workflow if needed.
- Tests/static gates: `windows/tests/Ping.Windows.App.Tests/*` or scripts.

**Steps:**
1. Decide self-contained EXE vs transparent thin downloader.
2. If self-contained: bundle MSIX + dependencies + certificate + scripts into EXE.
3. If thin downloader: implement visible progress states with current filename and URL domain.
4. Fix Inno progress mismatch or show a separate installer page/status message.
5. Reword launch checkbox; default should not surprise-open a giant app window.
6. Add static gates for hidden download calls / missing progress copy.
7. Build installer artifact.
8. Install on Windows and screenshot the installer progress.
9. Commit.

**Verification:**
- User can tell exactly what is being downloaded/installed.
- Progress does not lie.
- Install complete behavior matches messenger utility expectations.

---

### PR 6: Final parity QA pack

**Objective:** Only hand user a build after passing evidence-based QA.

**Files:**
- Create: `docs/qa/windows-parity-qa-YYYY-MM-DD.md`
- Attach screenshots/artifact links in PR.

**Steps:**
1. Build from latest `main` + feature branch.
2. Download artifacts like a user.
3. Install on Windows.
4. Run checklist:
   - Start menu click twice -> one window.
   - X closes to tray, process alive.
   - Tray opens app.
   - Room list looks like messenger.
   - Timeline looks like chat/video history.
   - Send text to room.
   - Send Face Ping if hardware available.
   - Incoming video opens floating playback.
   - Installer progress is transparent.
5. Capture screenshots/videos.
6. Write QA doc with pass/fail evidence.
7. Only then give user the Desktop QA pack.

---

## PR Body Template

Every PR must include:

```markdown
## What changed

## Which user complaints this fixes
- [ ] History opens twice from Start menu
- [ ] Home UI huge/ugly/debug-like
- [ ] Room/chat UI does not look like messenger
- [ ] Installer downloader feels hidden / progress mismatch

## Screenshots / Evidence
- Home:
- Room list:
- Timeline with chat:
- Timeline with video ping:
- Composer:
- Installer progress:

## Acceptance Criteria
- [ ] No duplicate History/Rooms windows
- [ ] Rooms are primary surface
- [ ] Timeline reads as chat/video-message history
- [ ] Utility/debug controls are not primary
- [ ] Installer is transparent

## Commands run

## Known remaining gaps
```

---

## Next Implementation Rule

The next attempt must not start by editing random XAML.

Start order:

1. Rebase on `origin/main` cleanly.
2. Mark failed PR37-style restyle as insufficient.
3. Lock the visual/product contract.
4. Fix single-instance duplicate-window bug.
5. Rebuild shell/rooms UI from messenger structure.
6. Build and screenshot before claiming success.

If the implementer cannot produce screenshots, the work is not complete.
