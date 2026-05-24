# Ping Windows Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows 사용자가 macOS 사용자와 같은 Supabase 룸에서 얼굴 메시지와 화면+얼굴 메시지를 주고받고, Windows에서도 Mac 앱과 거의 같은 tray/hotkey/mirror/playback UX를 경험하게 한다.

**Architecture:** 기존 macOS 앱은 그대로 유지하고 `windows/` 아래에 별도 Windows 네이티브 클라이언트를 추가한다. 두 클라이언트는 동일한 Supabase Anonymous Auth, RPC, private Storage bucket, MP4 메시지 계약을 공유하며, OS별 UI/권한/녹화/알림/업데이트만 각 플랫폼 네이티브로 구현한다. 화면+얼굴 즉시 전송은 Windows Graphics Capture desktop interop + native capture engine으로 구현해 global hotkey에서 picker 없이 3초 녹화와 전송을 시작한다.

**Tech Stack:** C#/.NET 10 LTS, WinUI 3 + Windows App SDK stable, packaged full-trust MSIX, C++/WinRT native capture engine, Win32 `RegisterHotKey`, Win32 notification area icon, Windows App SDK `AppNotificationManager`, Supabase REST/RPC over `HttpClient`.

---

## Product Invariants

- macOS 앱 불변식은 건드리지 않는다: macOS 13, Swift 6, `.pingGlassEffect()`, `SMAppService.mainApp`, Sparkle 설정을 변경하지 않는다.
- `Ping.xcodeproj` 직접 편집 금지. Windows 작업은 기본적으로 `windows/`, 공유 문서는 `docs/`, 필요 시 Supabase migration만 수정한다.
- Windows 클라이언트는 기존 서버 계약을 사용한다:
  - Storage bucket: `ping-videos`
  - Storage path: `<senderUid>/<videoId>.mp4`
  - `capture_mode`: `face_only` 또는 `screen_face`
  - `aspect_ratio`: face-only는 `1`, screen-face는 실제 영상 비율
  - `ping_create_message` 인자명은 macOS `MessageService`와 동일하게 유지한다.
- Mac ↔ Windows 상호 운용성은 기능 완료 조건이다. Windows에서 보낸 메시지는 Mac `VideoMessage`가 decode/playback해야 하고, Mac에서 보낸 메시지는 Windows가 decode/playback해야 한다.
- 송신 성공 시 별도 성공 toast를 띄우지 않는다. Mac과 동일하게 capture HUD/mirror만 fade-out한다.

## OS And API Constraints

기준 조사일: 2026-05-25.

- 1차 지원 OS는 **Windows 11 24H2 이상**으로 둔다. Windows 10은 2025-10-14 일반 지원이 끝났으므로 Windows 10 22H2/ESU 환경은 v1 범위에서 best-effort로만 다룬다.
- Windows App SDK는 production용 Stable channel만 사용한다. 2026-05-21 Microsoft 다운로드 페이지 기준 최신 stable인 `Microsoft.WindowsAppSDK` 2.1.3에 pin한다.
- .NET은 .NET 10 LTS를 기준으로 한다. .NET 8은 2026-11 지원 종료라 새 Windows 클라이언트의 장기 유지보수 기준으로 약하다.
- `RegisterHotKey`는 system-wide hotkey를 등록하지만 충돌 시 실패한다. 온보딩/Settings에서 충돌을 감지하고 대체 키를 녹음할 수 있어야 한다.
- Windows notification area 아이콘은 `Shell_NotifyIcon` 기반으로 구현한다. Windows 11에서는 사용자가 tray overflow에서 아이콘을 숨길 수 있으므로 온보딩에서 "항상 보이게 고정"을 안내하되 강제하지 않는다.
- Windows App SDK app notifications는 elevated/admin 앱에서 지원되지 않는다. Ping Windows는 일반 사용자 권한으로 실행해야 한다.
- Camera/mic은 `MediaCapture.InitializeAsync` 첫 호출에서 사용자 동의 prompt가 뜰 수 있고, 거부/OS privacy 차단 시 `E_ACCESSDENIED` 또는 `UnauthorizedAccessException`을 처리한다.
- Packaged 앱은 `Package.appxmanifest`에 `webcam`, `microphone`, `graphicsCapture` capability를 선언한다.
- 화면 캡처는 두 경로를 준비한다:
  - 기본 경로: `IGraphicsCaptureItemInterop.CreateForMonitor`로 현재/기본 모니터를 즉시 capture한다. 최소 Windows 10 1903 API지만, 제품 지원은 Windows 11 24H2+로 제한한다.
  - 보조 경로: `GraphicsCapturePicker`는 interop 실패 시 수동 테스트와 진단에만 사용한다.
- v1에서는 borderless capture를 요청하지 않는다. Windows의 capture border는 사용자의 시각적 안전장치로 둔다.
- DRM/protected content, secure desktop, 일부 GPU overlay는 검은 화면 또는 실패가 날 수 있다. 온보딩과 오류 UI에서 "화면 캡처가 제한된 콘텐츠는 전송되지 않을 수 있음"을 명시한다.

## UX Parity Contract

Windows 기본 단축키는 Mac의 Option 키를 Windows의 Alt 키로 대응한다.

| Mac UX | Windows UX | 설명 |
|---|---|---|
| Option+P | Alt+P | 얼굴만 원형 mirror 표시, Enter로 3초 녹화 후 review, review Enter로 전송 |
| Option+L | Alt+L | 화면+얼굴 mirror 표시, Enter로 3초 녹화 후 review, review Enter로 전송 |
| 신규 요구 | Alt+Shift+L | 화면+얼굴 quick send: 기본 룸 대상으로 즉시 3초 녹화/전송 |
| Option+O | Alt+O | 내 룸/히스토리 창 |
| Tab / 1-9 / 0/A / Esc / Enter | 동일 | 파트너 전환, 전체 발송, 닫기, 녹화 시작 |

Quick send 세부 동작:

- `Alt+Shift+L`을 누르면 마지막/기본 룸으로 바로 screen-face 녹화를 시작한다.
- 기본 룸이 없거나 sendable room이 없으면 history/room manager를 열고 명확한 오류 상태를 보여준다.
- 녹화 시작 전 300ms HUD를 띄워 사용자가 현재 대상과 캡처 모드를 인지하게 한다. `Esc`로 취소할 수 있다.
- 3초 녹화 중에는 작은 capture HUD와 빨간 border/countdown을 표시한다.
- 성공 시 HUD는 fade-out한다. 별도 성공 toast는 없다.
- 실패 시 HUD는 노란 border와 retry 상태를 유지하며 Enter 재시도, Esc 닫기를 지원한다.

Visual parity:

- Face-only mirror/playback: 200px circle.
- Screen-face mirror: Mac의 화면+얼굴 preview와 같은 비율을 사용하되, Windows에서는 360px wide compact preview를 기본으로 한다.
- Screen-face 영상 내부 face PIP: `ScreenFaceLayout.faceDiameterRatio = 0.32`에 맞춘다.
- Surface: Liquid Glass를 직접 복제하지 않고 Windows Fluent/Mica/Acrylic로 대응한다. 색/상태/둥근 정도는 Mac 디자인 토큰을 따른다.
- Border colors:
  - idle: white 30%, 1px
  - recording: `#FF3B30`, 2px
  - failed: `#FFCC00`, 2px
  - send all: rotating rainbow gradient, 2px

## Onboarding Contract

Windows onboarding은 Mac 권한 화면과 같은 정보 구조를 유지하되 Windows 제약을 정확히 반영한다.

1. OS/환경 확인
   - Windows 11 24H2+인지 확인한다.
   - unsupported Windows 10/old Windows 11이면 앱을 막지는 않되 "지원 대상 아님" 상태로 표시하고 screen-face quick send를 disabled한다.
   - admin/elevated로 실행 중이면 notifications 불가 안내 후 일반 권한 재실행 버튼을 제공한다.

2. Supabase config/session
   - `Supabase.json` 누락 시 명확한 안내.
   - Anonymous session 저장 위치: `%LOCALAPPDATA%\Ping\SupabaseSession.json`.
   - Windows와 Mac은 기기별 익명 계정이다. 같은 사람의 Mac/Windows identity 이전은 v1 범위 밖이며, 룸 초대/링크로 상호 연결한다.

3. Camera
   - packaged app에서는 `AppCapability.Create("Webcam").CheckAccess()`를 먼저 확인한다.
   - 실제 preview 초기화는 `MediaCapture.InitializeAsync`로 검증한다.
   - 실패 시 `ms-settings:privacy-webcam`과 `ms-settings:camera` 버튼을 제공한다.

4. Microphone
   - `MediaCapture` audio initialization으로 검증한다.
   - 실패 시 음성 없는 영상 fallback은 v1에서 제공하지 않는다. 전송 버튼을 막고 `ms-settings:privacy-microphone`으로 안내한다.

5. Screen capture
   - `GraphicsCaptureSession.IsSupported()`를 확인한다.
   - 현재 primary monitor에 대해 1-frame test capture를 수행한다.
   - 실패 시 screen-face 모드와 quick send를 disabled하고 진단 문자열을 표시한다.
   - Windows가 표시하는 capture border는 정상 동작임을 안내한다.

6. Notifications
   - `AppNotificationManager` 등록과 local notification test를 수행한다.
   - Windows 집중 지원/알림 설정 때문에 배너가 보이지 않을 수 있음을 안내하고 `ms-settings:privacy-notifications` 또는 notification settings로 연결한다.

7. Hotkeys
   - `Alt+P`, `Alt+L`, `Alt+Shift+L`, `Alt+O`를 `RegisterHotKey`로 등록 테스트한다.
   - 실패한 키는 "이미 다른 앱이 사용 중"으로 표시하고 recorder UI에서 재지정하게 한다.

8. Startup
   - packaged MSIX에서 `StartupTask`를 사용한다.
   - dev/unpackaged 실행에서는 startup toggle을 disabled하고 "패키징된 빌드에서 사용 가능"으로 표시한다.

## File Structure

```text
ping/
├── windows/
│   ├── PingWindows.sln
│   ├── README.md
│   ├── Directory.Build.props
│   ├── src/
│   │   ├── Ping.Windows.App/
│   │   │   ├── Ping.Windows.App.csproj
│   │   │   ├── app.manifest
│   │   │   ├── Package.appxmanifest
│   │   │   ├── App.xaml
│   │   │   ├── App.xaml.cs
│   │   │   ├── MainWindow.xaml
│   │   │   ├── MainWindow.xaml.cs
│   │   │   ├── Assets/
│   │   │   ├── Bootstrap/
│   │   │   ├── Hotkeys/
│   │   │   ├── Notifications/
│   │   │   ├── Onboarding/
│   │   │   ├── Playback/
│   │   │   ├── Setup/
│   │   │   ├── Tray/
│   │   │   └── UI/
│   │   ├── Ping.Windows.Core/
│   │   │   ├── Ping.Windows.Core.csproj
│   │   │   ├── Backend/
│   │   │   ├── Contracts/
│   │   │   ├── LocalState/
│   │   │   └── Models/
│   │   └── Ping.Windows.NativeCapture/
│   │       ├── Ping.Windows.NativeCapture.vcxproj
│   │       ├── include/
│   │       └── src/
│   ├── tests/
│   │   ├── Ping.Windows.Core.Tests/
│   │   └── Ping.Windows.App.Tests/
│   └── tools/
│       └── smoke/
└── docs/
    └── superpowers/plans/2026-05-25-windows-client.md
```

## Task 1: Scaffold Windows Solution

**Files:**
- Create: `windows/PingWindows.sln`
- Create: `windows/Directory.Build.props`
- Create: `windows/src/Ping.Windows.App/Ping.Windows.App.csproj`
- Create: `windows/src/Ping.Windows.Core/Ping.Windows.Core.csproj`
- Create: `windows/src/Ping.Windows.NativeCapture/Ping.Windows.NativeCapture.vcxproj`
- Create: `windows/tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj`
- Create: `windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj`
- Create: `windows/README.md`

- [ ] **Step 1: Verify Windows dev environment**

Run on a Windows 11 24H2+ machine:

```powershell
dotnet --version
dotnet --list-sdks
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Workload.ManagedDesktop Microsoft.VisualStudio.Workload.NativeDesktop -property installationVersion
```

Expected:

- `dotnet --version` starts with `10.`
- Visual Studio has the .NET desktop development workload, Desktop development with C++, and Windows App SDK tooling.

- [ ] **Step 2: Create the solution skeleton**

Run:

```powershell
mkdir windows
cd windows
dotnet new sln -n PingWindows
dotnet new classlib -n Ping.Windows.Core -o src/Ping.Windows.Core -f net10.0
dotnet new xunit -n Ping.Windows.Core.Tests -o tests/Ping.Windows.Core.Tests -f net10.0
dotnet new xunit -n Ping.Windows.App.Tests -o tests/Ping.Windows.App.Tests -f net10.0
dotnet sln add src/Ping.Windows.Core/Ping.Windows.Core.csproj
dotnet sln add tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj
dotnet sln add tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj
dotnet add tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj reference src/Ping.Windows.Core/Ping.Windows.Core.csproj
dotnet add tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj reference src/Ping.Windows.Core/Ping.Windows.Core.csproj
```

- [ ] **Step 3: Add WinUI app from Visual Studio template**

Use Visual Studio: `Blank App, Packaged (WinUI 3 in Desktop)` and save it to:

```text
windows/src/Ping.Windows.App/
```

Then add it:

```powershell
dotnet sln windows/PingWindows.sln add windows/src/Ping.Windows.App/Ping.Windows.App.csproj
dotnet add windows/src/Ping.Windows.App/Ping.Windows.App.csproj reference windows/src/Ping.Windows.Core/Ping.Windows.Core.csproj
```

- [ ] **Step 4: Add build props**

Create `windows/Directory.Build.props`:

```xml
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest</AnalysisLevel>
  </PropertyGroup>
</Project>
```

- [ ] **Step 5: Verify build**

Run:

```powershell
dotnet test windows/PingWindows.sln
```

Expected: `Ping.Windows.Core.Tests` passes. WinUI packaging build may require Visual Studio/MSBuild; document any CLI limitation in `windows/README.md`.

- [ ] **Step 6: Commit**

```bash
git add windows
git commit -m "feat(windows): scaffold native client workspace"
```

## Task 2: Shared Backend Contracts And Supabase Client

**Files:**
- Create: `windows/src/Ping.Windows.Core/Models/CaptureMode.cs`
- Create: `windows/src/Ping.Windows.Core/Models/MirrorPosition.cs`
- Create: `windows/src/Ping.Windows.Core/Models/Room.cs`
- Create: `windows/src/Ping.Windows.Core/Models/VideoMessage.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/SupabaseClient.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/MessageService.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/StorageService.cs`
- Create: `windows/tests/Ping.Windows.Core.Tests/BackendContractTests.cs`

- [ ] **Step 1: Write contract tests**

Create `BackendContractTests.cs` with tests for JSON names and raw values:

```csharp
using System.Text.Json;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Tests;

public sealed class BackendContractTests
{
    [Fact]
    public void CaptureMode_UsesMacCompatibleRawValues()
    {
        Assert.Equal("face_only", CaptureMode.FaceOnly.ToWireValue());
        Assert.Equal("screen_face", CaptureMode.ScreenFace.ToWireValue());
        Assert.Equal(CaptureMode.ScreenFace, CaptureModeWire.Parse("screen_face"));
    }

    [Fact]
    public void VideoMessage_DecodesMacPayloadShape()
    {
        var json = """
        {
          "id": "message-1",
          "room_id": "room-1",
          "sender_uid": "sender",
          "receiver_uid": "receiver",
          "sender_nickname": "Youngmin",
          "video_id": "video-1",
          "video_url": "sender/video-1.mp4",
          "duration_ms": 3000,
          "mirror_position": { "xRatio": 0.4, "yRatio": 0.6 },
          "status": "uploaded",
          "expires_at": "2026-05-26T00:00:00.000Z",
          "capture_mode": "screen_face",
          "aspect_ratio": 1.7777778,
          "allows_local_save": true
        }
        """;

        var message = JsonSerializer.Deserialize<VideoMessage>(json, JsonOptions.Supabase)!;

        Assert.Equal("room-1", message.RoomId);
        Assert.Equal(CaptureMode.ScreenFace, message.CaptureMode);
        Assert.Equal(0.4, message.MirrorPosition.XRatio, precision: 6);
        Assert.True(message.AllowsLocalSave);
    }
}
```

- [ ] **Step 2: Implement model serialization**

Use `JsonPropertyName` attributes matching Swift `CodingKeys`. `CaptureModeWire` must be explicit; do not rely on enum names.

```csharp
namespace Ping.Windows.Core.Models;

public enum CaptureMode
{
    FaceOnly,
    ScreenFace
}

public static class CaptureModeWire
{
    public static string ToWireValue(this CaptureMode mode) => mode switch
    {
        CaptureMode.FaceOnly => "face_only",
        CaptureMode.ScreenFace => "screen_face",
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, null)
    };

    public static CaptureMode Parse(string value) => value switch
    {
        "face_only" => CaptureMode.FaceOnly,
        "screen_face" => CaptureMode.ScreenFace,
        _ => throw new JsonException($"Unknown capture mode: {value}")
    };
}
```

- [ ] **Step 3: Implement `SupabaseClient`**

Implement `rpcArray<T>`, `rpcValue<T>`, `rpcVoid`, anonymous auth bootstrap, refresh, and session persistence under `%LOCALAPPDATA%\Ping\SupabaseSession.json`. Keep the runtime config in `%LOCALAPPDATA%\Ping\Supabase.json` for dev and packaged app resources for release.

- [ ] **Step 4: Implement message send contract**

`MessageService.SendAsync` must call `ping_create_message` with this exact body:

```json
{
  "room_uuid": "<room-id>",
  "receiver_uid": "<receiver-uid>",
  "sender_nickname_text": "<nickname>",
  "video_id_text": "<shared-video-id>",
  "video_url_text": "<storage-path>",
  "x_ratio": 0.5,
  "y_ratio": 0.5,
  "capture_mode_text": "screen_face",
  "aspect_ratio_value": 1.7777778,
  "allows_local_save_value": false
}
```

- [ ] **Step 5: Run tests**

```powershell
dotnet test windows/tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj
```

Expected: contract tests pass without network.

- [ ] **Step 6: Commit**

```bash
git add windows/src/Ping.Windows.Core windows/tests/Ping.Windows.Core.Tests
git commit -m "feat(windows): add supabase backend contracts"
```

## Task 3: Windows Onboarding And Permission Diagnostics

**Files:**
- Create: `windows/src/Ping.Windows.App/Onboarding/OnboardingWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Onboarding/OnboardingViewModel.cs`
- Create: `windows/src/Ping.Windows.App/Onboarding/PermissionProbe.cs`
- Create: `windows/src/Ping.Windows.App/Onboarding/WindowsVersionProbe.cs`
- Create: `windows/src/Ping.Windows.App/Onboarding/SettingsLauncher.cs`
- Modify: `windows/src/Ping.Windows.App/Package.appxmanifest`
- Test: `windows/tests/Ping.Windows.App.Tests/OnboardingStateTests.cs`

- [ ] **Step 1: Add manifest capabilities**

`Package.appxmanifest` must include:

```xml
<Capabilities>
  <Capability Name="internetClient" />
  <uap6:Capability Name="graphicsCapture" />
  <DeviceCapability Name="webcam" />
  <DeviceCapability Name="microphone" />
</Capabilities>
```

Do not add `graphicsCaptureWithoutBorder` in v1.

- [ ] **Step 2: Implement version policy**

`WindowsVersionProbe` returns:

```csharp
public enum WindowsSupportStatus
{
    Supported,
    UnsupportedWindows10,
    UnsupportedOldWindows11
}
```

Rules:

- Windows 11 24H2+ => `Supported`
- Windows 11 below 24H2 => `UnsupportedOldWindows11`
- Windows 10 => `UnsupportedWindows10`

- [ ] **Step 3: Implement permission probes**

`PermissionProbe` checks:

- camera capability status and `MediaCapture.InitializeAsync`
- microphone capability status and `MediaCapture.InitializeAsync`
- `GraphicsCaptureSession.IsSupported()`
- one-frame monitor capture through native capture self-test
- `AppNotificationManager` registration
- `RegisterHotKey` dry-run for all defaults

- [ ] **Step 4: Implement settings launchers**

Use:

```csharp
await Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-webcam"));
await Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-microphone"));
await Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-notifications"));
await Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-graphicscaptureprogrammatic"));
```

The graphics URI is shown only for programmatic capture failures where Windows exposes that page. For desktop interop failures, show diagnostic copy and a retry button.

- [ ] **Step 5: Implement onboarding UI**

The first screen is the actual setup workflow, not marketing. Use compact rows:

- Windows version
- Supabase config
- Camera
- Microphone
- Screen capture
- Notifications
- Hotkeys
- Startup

Each row has status, retry, and settings/action button. Avoid long explanatory text; use a short error string only when blocked.

- [ ] **Step 6: Run onboarding state tests**

```powershell
dotnet test windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj --filter OnboardingStateTests
```

Expected: supported/unsupported/blocked states map to the correct CTA.

- [ ] **Step 7: Commit**

```bash
git add windows/src/Ping.Windows.App/Onboarding windows/src/Ping.Windows.App/Package.appxmanifest windows/tests/Ping.Windows.App.Tests
git commit -m "feat(windows): add onboarding permission checks"
```

## Task 4: Tray App, Hotkeys, And App Shell

**Files:**
- Create: `windows/src/Ping.Windows.App/Tray/TrayIconController.cs`
- Create: `windows/src/Ping.Windows.App/Hotkeys/GlobalHotkeyManager.cs`
- Create: `windows/src/Ping.Windows.App/Hotkeys/HotkeyBinding.cs`
- Create: `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- Modify: `windows/src/Ping.Windows.App/App.xaml.cs`
- Modify: `windows/src/Ping.Windows.App/MainWindow.xaml`
- Test: `windows/tests/Ping.Windows.App.Tests/HotkeyBindingTests.cs`

- [ ] **Step 1: Add hotkey tests**

Cover:

- default `Alt+P`, `Alt+L`, `Alt+Shift+L`, `Alt+O`
- conflict state
- unregister on app shutdown
- settings persistence under `%LOCALAPPDATA%\Ping\UserPreferences.json`

- [ ] **Step 2: Implement `GlobalHotkeyManager`**

Use Win32 `RegisterHotKey` and listen for `WM_HOTKEY` on a hidden message window. Expose:

```csharp
public sealed class GlobalHotkeyManager : IDisposable
{
    public event EventHandler<HotkeyCommand>? HotkeyPressed;
    public HotkeyRegistrationResult Register(HotkeyCommand command, HotkeyBinding binding);
    public void UnregisterAll();
}
```

- [ ] **Step 3: Implement tray icon**

Use `Shell_NotifyIcon` with:

- left click: open room/history window
- right click menu: Open Ping, New Face Ping, New Screen+Face Ping, Quick Screen+Face Ping, Settings, Quit
- recreate icon on `TaskbarCreated` shell message

- [ ] **Step 4: Wire app commands**

`AppCoordinator` maps:

- `FacePing` => show face mirror
- `ScreenFacePing` => show screen-face mirror
- `QuickScreenFacePing` => immediate screen-face send
- `History` => show room/history window

- [ ] **Step 5: Run app shell smoke test**

Manual:

1. Launch packaged app.
2. Confirm tray icon appears.
3. Press `Alt+P`, `Alt+L`, `Alt+Shift+L`, `Alt+O`.
4. Confirm each command reaches a visible state or clear blocked state.

- [ ] **Step 6: Commit**

```bash
git add windows/src/Ping.Windows.App/Tray windows/src/Ping.Windows.App/Hotkeys windows/src/Ping.Windows.App/Bootstrap windows/tests/Ping.Windows.App.Tests
git commit -m "feat(windows): add tray and global hotkeys"
```

## Task 5: Face-Only Mirror Recording And Send

**Files:**
- Create: `windows/src/Ping.Windows.App/UI/PingDesign.xaml`
- Create: `windows/src/Ping.Windows.App/UI/RainbowBorder.xaml`
- Create: `windows/src/Ping.Windows.App/Capture/FaceMirrorWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Capture/FaceMirrorViewModel.cs`
- Create: `windows/src/Ping.Windows.App/Capture/FaceRecorder.cs`
- Create: `windows/src/Ping.Windows.Core/LocalState/LocalArchive.cs`
- Test: `windows/tests/Ping.Windows.Core.Tests/LocalArchiveTests.cs`

- [ ] **Step 1: Add design resources**

Implement shared resources:

- `PingSurfaceBrush`
- `PingBorderIdleBrush`
- `PingBorderRecordingBrush`
- `PingBorderFailedBrush`
- `PingCornerRadius = 16`
- circular clip helper for 200px mirror/playback

- [ ] **Step 2: Implement face recorder**

Use `MediaCapture` and `PrepareLowLagRecordToStorageFileAsync` or equivalent to create MP4:

- 1920x1080 preferred
- H.264 video
- AAC audio
- exact 3 seconds via timer stop guard
- output temp file under `%TEMP%\Ping\`

- [ ] **Step 3: Implement face mirror state machine**

States:

```csharp
public enum MirrorState
{
    Idle,
    Recording,
    Uploading,
    Failed
}
```

Transitions:

- Idle + Enter => Recording
- Recording complete => Uploading
- Upload success => fade-out close
- Upload failure => Failed
- Failed + Enter => Recording
- Any state + Esc => close/cancel

- [ ] **Step 4: Send to Supabase**

Use `MessageService.SendAsync` with:

- `capture_mode_text = "face_only"`
- `aspect_ratio_value = 1`
- `x_ratio`/`y_ratio` from mirror window center relative to primary display

- [ ] **Step 5: Manual Mac interop test**

1. Windows sends face-only ping to a room containing a Mac user.
2. Mac receives notification.
3. Mac playback opens at the sender position and plays exactly 3 seconds.
4. Windows Storage object path is `<windowsSenderUid>/<videoId>.mp4`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/Ping.Windows.App/UI windows/src/Ping.Windows.App/Capture windows/src/Ping.Windows.Core/LocalState windows/tests
git commit -m "feat(windows): send face-only video pings"
```

## Task 6: Native Screen+Face Capture Engine

**Files:**
- Create: `windows/src/Ping.Windows.NativeCapture/include/PingCaptureEngine.h`
- Create: `windows/src/Ping.Windows.NativeCapture/src/PingCaptureEngine.cpp`
- Create: `windows/src/Ping.Windows.NativeCapture/src/MonitorCapture.cpp`
- Create: `windows/src/Ping.Windows.NativeCapture/src/CameraFrameSource.cpp`
- Create: `windows/src/Ping.Windows.NativeCapture/src/ScreenFaceCompositor.cpp`
- Create: `windows/src/Ping.Windows.NativeCapture/src/Mp4SinkWriter.cpp`
- Create: `windows/src/Ping.Windows.App/Capture/NativeCaptureEngine.cs`
- Test: `windows/tools/smoke/ScreenFaceCaptureSmoke.ps1`

- [ ] **Step 1: Implement native API surface**

Expose a small C ABI:

```cpp
extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4(
    const wchar_t* outputPath,
    int durationMs,
    int targetMonitorIndex,
    double faceDiameterRatio,
    double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_SelfTestScreenCapture();
```

Return `0` on success. Return stable nonzero error codes for unsupported OS, access denied, no monitor, no camera, encoder failure, and protected content.

- [ ] **Step 2: Implement monitor capture**

Use `IGraphicsCaptureItemInterop.CreateForMonitor` to create a `GraphicsCaptureItem` for the selected monitor. The default monitor is the primary monitor; multi-monitor selection uses the monitor containing the mirror window or quick-send HUD.

- [ ] **Step 3: Implement compositing**

Composite each screen frame to a D3D11 render target:

- output size max width 1920, preserving screen aspect ratio
- face PIP diameter = shortest output side * `0.32`
- face PIP bottom-right with 24px margin
- circular mask for face PIP
- SDR output; tone-map HDR to SDR if the source format is HDR

- [ ] **Step 4: Implement MP4 encoding**

Use Media Foundation Sink Writer:

- video: H.264, 30fps, target bitrate 6-10 Mbps
- audio: AAC from microphone, 48kHz
- duration: exactly 3000ms with stop guard
- container: `.mp4`

- [ ] **Step 5: Implement C# wrapper**

`NativeCaptureEngine.RecordScreenFaceAsync`:

```csharp
public sealed record ScreenFaceCaptureResult(
    string FilePath,
    double AspectRatio);

public interface IScreenFaceCaptureEngine
{
    Task<ScreenFaceCaptureResult> RecordAsync(
        TimeSpan duration,
        int monitorIndex,
        CancellationToken cancellationToken);

    Task<ScreenCaptureSelfTestResult> SelfTestAsync();
}
```

- [ ] **Step 6: Smoke test output**

Run:

```powershell
windows/tools/smoke/ScreenFaceCaptureSmoke.ps1
```

Expected:

- MP4 exists
- duration is 2.9-3.2 seconds
- resolution is at least 1280px wide unless monitor is smaller
- face PIP is visible in the bottom-right
- file plays in Windows Media Player and macOS QuickTime

- [ ] **Step 7: Commit**

```bash
git add windows/src/Ping.Windows.NativeCapture windows/src/Ping.Windows.App/Capture/NativeCaptureEngine.cs windows/tools/smoke
git commit -m "feat(windows): capture screen-face mp4 messages"
```

## Task 7: Screen+Face Mirror And Quick Send Hotkey

**Files:**
- Create: `windows/src/Ping.Windows.App/Capture/ScreenFaceMirrorWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Capture/ScreenFaceMirrorViewModel.cs`
- Create: `windows/src/Ping.Windows.App/Capture/QuickSendHudWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Capture/QuickSendController.cs`
- Modify: `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- Test: `windows/tests/Ping.Windows.App.Tests/QuickSendStateTests.cs`

- [ ] **Step 1: Implement `Alt+L` screen-face mirror**

Behavior:

- show compact screen-face preview window
- partner chip identical to face-only mirror
- Enter records 3 seconds, then shows review playback
- Review Enter sends; Backspace/Delete discards and records again
- upload uses `capture_mode_text = "screen_face"`
- upload uses native engine `AspectRatio`
- success fade-out, no success toast

- [ ] **Step 2: Implement `Alt+Shift+L` quick send**

Behavior:

- resolve default room from remote profile + local preferences
- if no room, open room manager with blocked state
- show 300ms HUD with room name and "화면+얼굴"
- start native 3s recording automatically
- send immediately after encode
- Esc cancels during HUD/recording before upload starts
- if upload starts, Esc hides HUD but does not cancel the already-started upload

- [ ] **Step 3: Add privacy guardrails**

Quick send is disabled until onboarding screen capture self-test, camera, microphone, and default room are all green. Settings includes a toggle:

```text
화면+얼굴 빠른 전송 사용
```

Default: on after successful onboarding. If user turns it off, `Alt+Shift+L` opens screen-face mirror instead of recording immediately.

- [ ] **Step 4: Run state tests**

```powershell
dotnet test windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj --filter QuickSendStateTests
```

Expected:

- no room => opens room manager
- missing screen permission => opens onboarding permission row
- enabled quick send => records immediately
- disabled quick send => opens screen-face mirror

- [ ] **Step 5: Manual Mac interop test**

1. Windows sends `Alt+Shift+L` quick screen-face ping.
2. Mac history shows `capture_mode = screen_face`.
3. Mac expanded playback uses the stored `aspect_ratio`.
4. Mac can play the MP4.

- [ ] **Step 6: Commit**

```bash
git add windows/src/Ping.Windows.App/Capture windows/src/Ping.Windows.App/Bootstrap windows/tests
git commit -m "feat(windows): add screen-face quick send"
```

## Task 8: Incoming Polling, Notifications, And Playback

**Files:**
- Create: `windows/src/Ping.Windows.App/Notifications/NotificationController.cs`
- Create: `windows/src/Ping.Windows.App/Playback/PlaybackWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Playback/PlaybackViewModel.cs`
- Create: `windows/src/Ping.Windows.App/Playback/VideoPlayerHost.cs`
- Modify: `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`
- Test: `windows/tests/Ping.Windows.App.Tests/IncomingMessageDedupTests.cs`

- [ ] **Step 1: Implement polling**

Poll `ping_incoming_messages()` every 2 seconds after bootstrap. Keep both duplicate defenses:

- per-stream `yieldedIds`
- app-wide `notifiedMessageIds` persisted for the session

- [ ] **Step 2: Implement local notifications**

Use `AppNotificationManager` and encode `message_id` in activation arguments. Notification click:

1. call `ping_get_message(message_uuid)`
2. download Storage object
3. open playback window
4. after first playback end, call `ping_mark_message_seen(message_uuid)` once
5. keep the window briefly for Enter replay or Esc close, then fade out after about 10 seconds of idle time

- [ ] **Step 3: Implement playback window**

Face-only:

- 200px circular borderless topmost window
- position from sender `x_ratio`/`y_ratio` mapped to primary monitor work area

Screen-face:

- preserve `aspect_ratio`
- use compact playback by default
- support direct playback from history rows

- [ ] **Step 4: Run Windows receives Mac test**

1. Mac sends face-only.
2. Windows shows one notification.
3. Click notification.
4. Windows downloads and plays 3 seconds.
5. Message status becomes `seen`.
6. Repeat with Mac screen-face message.

- [ ] **Step 5: Commit**

```bash
git add windows/src/Ping.Windows.App/Notifications windows/src/Ping.Windows.App/Playback windows/tests
git commit -m "feat(windows): receive and play video pings"
```

## Task 9: Rooms, Invitations, History, Chat, And Settings

**Files:**
- Create: `windows/src/Ping.Windows.App/Setup/RoomManagerWindow.xaml`
- Create: `windows/src/Ping.Windows.App/Setup/RoomManagerViewModel.cs`
- Create: `windows/src/Ping.Windows.App/Setup/SettingsWindow.xaml`
- Create: `windows/src/Ping.Windows.App/History/HistoryWindow.xaml`
- Create: `windows/src/Ping.Windows.App/History/HistoryViewModel.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/RoomService.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/InvitationService.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/ChatMessageService.cs`
- Create: `windows/src/Ping.Windows.Core/Backend/ReactionService.cs`
- Test: `windows/tests/Ping.Windows.Core.Tests/RoomContractTests.cs`

- [ ] **Step 1: Implement room/invite RPC wrappers**

Implement the same RPC names used by macOS:

- `ping_create_room`
- `ping_my_rooms`
- `ping_search_open_rooms`
- `ping_join_room`
- `ping_leave_room`
- `ping_rename_room`
- `ping_invite_user`
- `ping_send_invitation`
- `ping_accept_invitation`
- `ping_reject_invitation`
- `ping_create_invite_link`
- `ping_accept_invite_link`

- [ ] **Step 2: Implement room manager UI**

Keep it visually close to Mac:

- compact sidebar
- room detail panel
- invite/search controls
- no decorative landing page

- [ ] **Step 3: Implement history UI**

Show:

- video rows
- direct video playback from each history row
- sender labels for group rooms
- chat messages and image attachments if supported by current backend
- reactions if supported by current backend

- [ ] **Step 4: Implement settings UI**

Tabs:

- General: startup, nickname
- Hotkeys: Alt+P, Alt+L, Alt+Shift+L, Alt+O
- Rooms
- Storage
- Info/update

- [ ] **Step 5: Commit**

```bash
git add windows/src/Ping.Windows.App/Setup windows/src/Ping.Windows.App/History windows/src/Ping.Windows.Core/Backend windows/tests
git commit -m "feat(windows): add rooms history and settings"
```

## Task 10: Packaging, Updates, CI, And Cross-Platform QA

**Files:**
- Create: `windows/scripts/build-release.ps1`
- Create: `windows/scripts/smoke-release.ps1`
- Create: `.github/workflows/windows-client.yml`
- Modify: `README.md`
- Modify: `PING_PROJECT_SPECIFICATION.md`
- Create: `docs/WINDOWS_APP_SETUP.md`

- [ ] **Step 1: Build packaged MSIX**

Release script outputs:

```text
windows/dist/Ping-Windows-v<version>-x64.msix
windows/dist/Ping-Windows-v<version>-arm64.msix
```

Use signed packages for external distribution. If signing is not ready, document SmartScreen behavior honestly.

- [ ] **Step 2: Select updater**

Use one of:

- MSIX app installer update feed for direct distribution
- Microsoft Store update if Store distribution is chosen
- Velopack only if MSIX feed cannot satisfy update UX

Do not reuse Sparkle for Windows.

- [ ] **Step 3: Add CI**

CI must run:

```powershell
dotnet test windows/PingWindows.sln
msbuild windows/PingWindows.sln /p:Configuration=Release /p:Platform=x64
```

Native capture smoke tests are hardware/desktop-session dependent and run manually or on a dedicated Windows runner.

- [ ] **Step 4: Update docs/spec**

Update docs with:

- Windows supported OS: Windows 11 24H2+
- Windows hotkeys
- Windows onboarding permissions
- Mac/Windows interoperability
- Windows install/update path
- Windows 10 best-effort status

- [ ] **Step 5: Cross-platform QA matrix**

Run:

| Sender | Receiver | Mode | Expected |
|---|---|---|---|
| Windows | Mac | face_only | Mac notification/playback/seen |
| Windows | Mac | screen_face | Mac expanded playback uses aspect_ratio |
| Mac | Windows | face_only | Windows notification/playback/seen |
| Mac | Windows | screen_face | Windows playback preserves aspect_ratio |
| Windows | Windows | Alt+Shift+L quick | Immediate screen-face send |
| Mac | Mac | existing | No regression |

- [ ] **Step 6: Commit**

```bash
git add windows/scripts .github/workflows README.md PING_PROJECT_SPECIFICATION.md docs/WINDOWS_APP_SETUP.md
git commit -m "release(windows): add packaging and qa workflow"
```

## Execution Notes

- Implement in a Windows development environment. The current macOS workspace can hold the plan and review code, but WinUI/native capture verification requires Windows hardware or a Windows VM with camera, microphone, and interactive desktop capture support.
- Prefer TDD for backend contracts, state machines, serialization, storage path generation, hotkey binding parsing, onboarding state mapping, and duplicate notification suppression.
- Use manual smoke tests for camera, microphone, notification activation, screen capture, and native encoder output because those depend on OS consent and hardware.
- Do not change Supabase SQL unless Windows uncovers a real cross-platform contract gap. If SQL changes are needed, make them additive and prove macOS remains compatible.
- Keep Windows-specific assets under `windows/`; do not reuse macOS `Resources/Supabase.plist`. Windows config format is `Supabase.json`.

## Reference Sources

- Windows App SDK overview and release channels: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
- Windows App SDK notifications: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/notifications/app-notifications/
- Windows notifications API selection: https://learn.microsoft.com/en-us/windows/apps/develop/notifications/
- Camera and MediaCapture: https://learn.microsoft.com/en-us/windows/apps/develop/camera/basic-photo-capture
- Camera privacy handling: https://learn.microsoft.com/en-us/windows/apps/develop/camera/camera-privacy-setting
- Windows settings URI scheme: https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings
- Windows Graphics Capture: https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/screen-capture
- Graphics capture desktop interop: https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nn-windows-graphics-capture-interop-igraphicscaptureiteminterop
- App capability declarations: https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations
- RegisterHotKey: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey
- Notification area/Shell_NotifyIcon: https://learn.microsoft.com/en-us/windows/win32/shell/notification-area
- Windows 10 lifecycle: https://learn.microsoft.com/en-us/windows/release-health/release-information
- Windows 11 lifecycle: https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro
- .NET support policy: https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core
