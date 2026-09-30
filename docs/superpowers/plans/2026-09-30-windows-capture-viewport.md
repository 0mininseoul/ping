# Windows Capture Viewport and Mirror Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, task-by-task, then one fresh whole-milestone reviewer. The approved full-parity strategy and continuous completion request authorize execution without another design checkpoint.

**Goal:** Show the complete Mac-style mirror at the current Windows display scale, preview and record the same selected screen region, and keep screen-face recording memory and cancellation bounded.

**Reference:** `Ping/Capture/ScreenCaptureViewport.swift`, `Ping/UI/Mirror/MirrorView.swift`, `MirrorWindow.swift`, `ScreenCaptureManager.swift`. Mac zoom1..4, Option-wheel/pinch, pointer center while Option held, Option0 reset, frozen recording viewport; face200pt; screen long side480pt with actual display aspect. Windows uses Alt, system font, native always-on-top borderless windows, existing target/review/red-border/fade UX. Internal capture pixels remain top-origin; convert only the message position at the existing wire boundary.

**Audit:** Legacy Windows mirrors size AppWindow in physical pixels while XAML requests DIP, and fixed480x270 screen preview crops other display aspects. Native capture retains all screen/camera frames before encoding; high resolution can consume gigabytes. These are product defects to fix, not evidence of hardware QA completion.

## Task1 — Pure viewport and mirror geometry

Files: Core `Capture/ScreenCaptureViewport.cs`, `CaptureMirrorLayout.cs`, corresponding tests.

- [x] RED tests: zoom1..4, stable nonfinite inputs, edge-center inset, full/zoomed crop, negative monitor origins, pointer outside capture display, reset and fractional wheel; face200 and screen long-side480 geometry, portrait/ultrawide,100/150/200% scale, small work-area clamp.
- [x] Immutable viewport and validated layout contracts. Full Core/App suites GREEN. Commit `feat(windows-capture): define viewport and mirror geometry`.

## Task2 — Native crop, composition and ABI

Files: native header/engine/compositor/writer, new pure native viewport helpers and synthetic native tests; managed NativeCaptureEngine/OwnedScreenFaceCaptureEngine contracts and fake engines.

- [x] RED synthetic colored frame tests for center/edge crop, nearest-source sampling, aspect, camera-circle overlay, row pitch, odd source dimensions and invalid bounds. Never capture the desktop or camera in these tests.
- [x] Add versioned native entry points with explicit zoom/center and cancellation handle, keep old entry points as full-screen compatibility wrappers. Use one validated crop in preview and record; sanitize/check dimensions and overflow. H264 output dimensions must be valid. Cancellation waits actual native cleanup before handle/lease release. Managed fake checks verify immutable viewport snapshots and cleanup.
- [x] Native synthetic tests, Core/App and x64 native/WinUI build GREEN. Commit `feat(windows-capture): apply viewport to native preview and recording`.

## Task3 — Bounded recording pipeline

Files: MonitorCapture/CameraFrameSource/Mp4SinkWriter/engine and owned native fixtures.

- [ ] Replace retained whole-session frame vectors with bounded producers and incremental encoder writes. Use capture timestamps/shared recording start for synchronization, bounded queues, callback drain, clean cancellation and explicit startup/error propagation. Resize/crop before retained CPU buffers. Normalize camera signed stride/orientation and check source resize. Do not infer protected content solely from a valid all-black frame. Preserve H264/AAC,3second duration and private temporary output cleanup. Match Mac540px long-side/1.2Mbps screen video and64kbps mono audio; keep preview crisp independently.
- [ ] Deterministic fake producer tests cover slow source/writer, early failure, cancellation and peak retained frame bytes; synthetic3second MP4 fixture validates duration/audio/video/selected region without hardware. Record measured memory bound. Commit `refactor(windows-capture): stream bounded synchronized recording frames`.

## Task4 — DPI-correct mirror and viewport interaction

Files: mirror XAML/native windows/view models, owned input adapter, reusable native window layout helpers, diagnostic fixture.

- [ ] Remove fixed physical sizing/CompactOverlay dimensions; use actual display aspect and200/480DIP geometry, native borderless always-on-top, circular face and16DIP rounded screen region. Resize on scale/display changes, clamp to work area and support drag. Exclude owned Ping windows from capture, matching Mac's application exclusion. Save existing local position preference; derive sender position against full display bounds before the existing top→bottom wire conversion. Face-only exports must use central square crop like Mac, with a synthetic clip check.
- [ ] Alt-wheel and pointer tracking while screen mirror is editable, supported pinch route, Alt0 reset, visible short Korean guidance and zoom value. Modifier handling precedes target-selection0; plain target keys remain. No global listener survives window closure; frozen viewport is used for the entire recording and reviewed clip. Redo restores editable preview safely through shared camera cleanup.
- [ ] Fake adapters plus actual isolated WinUI mirrors with synthetic preview: client size/current DPI/aspect/native region/drag positioning/reset/repeat Enter/review/redo/close. No actual desktop/camera/account capture. Full suites and x64 Release GREEN. Commit `feat(windows-capture): align mirror viewport and display scale with Mac`.

## Task5 — Review and verification

- [ ] One fresh whole-milestone reviewer; fix verified Important/Critical findings with behavioral regression evidence. Review native buffer/cancellation/encoder ownership as well as UI.
- [ ] Normal x64 Release/MSIX, fixture exclusion and synthetic capture report. Document real camera/microphone/DPI monitor transition/performance/Mac/ARM64 QA still unverified; do not call synthetic capture hardware QA. Commit `docs(windows): verify capture viewport milestone`.
- [ ] Continue account/device/settings/EXE/update and actual-device QA under the existing full goal. No operational backend changes or publishing for this milestone.
