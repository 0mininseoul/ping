# Ping Windows App Setup

Ping for Windows is a native WinUI 3 client that shares the same Supabase backend, room model, private `ping-videos` Storage bucket, and MP4 message contract as the macOS app.

## Support Policy

- Primary OS: Windows 11 24H2 or later.
- Packaged MSIX installs require Windows 11 24H2 or later because the app targets Windows SDK `10.0.26100.0`.
- Windows 10 and older Windows 11 builds are out of the packaged v1 support range. Future unpackaged/dev experiments may probe APIs at runtime, but release packages should be treated as 24H2+ only.
- Windows App SDK: stable channel, pinned to `Microsoft.WindowsAppSDK` `2.1.3`.
- .NET SDK: 10.x.
- Visual Studio: .NET desktop development, Desktop development with C++, Windows App SDK tooling, and Windows SDK `10.0.26100.0` or newer.

## Runtime Supabase Config

Create this file on the Windows machine:

```text
%LOCALAPPDATA%\Ping\Supabase.json
```

```json
{
  "url": "https://YOUR_PROJECT_REF.supabase.co",
  "anonKey": "YOUR_SUPABASE_ANON_KEY"
}
```

The Windows client stores its anonymous session separately at:

```text
%LOCALAPPDATA%\Ping\SupabaseSession.json
```

Windows and Mac installations are separate anonymous identities. Connect them through room invitations or invite links.

## Hotkeys

| macOS | Windows | Behavior |
|---|---|---|
| Option+P | Alt+P | Face-only mirror, Enter records/sends |
| Option+L | Alt+L | Screen+face mirror, Enter records/sends |
| none | Alt+Shift+L | Quick screen+face send to default room |
| Option+O | Alt+O | Room history |

If a hotkey is already used by another app, onboarding/settings show it as conflicted and Settings > Hotkeys lets the user apply a different Ctrl/Alt/Shift/Win + key binding. Ping saves the new binding only after Windows accepts the global hotkey registration.

## Onboarding Checks

1. OS support: show unsupported warning outside Windows 11 24H2+ and disable screen+face quick send when required APIs are unavailable.
2. Admin/elevated state: app notifications are not supported for elevated apps, so users should restart Ping normally.
3. Camera: check packaged webcam capability and initialize MediaCapture.
4. Microphone: initialize audio capture; v1 does not provide silent-video fallback.
5. Screen capture: check `GraphicsCaptureSession.IsSupported()` and run the native one-frame monitor self-test.
6. Notifications: register Windows App SDK notifications and show a local test notification.
7. Hotkeys: register Alt+P, Alt+L, Alt+Shift+L, and Alt+O with Win32 `RegisterHotKey`.
8. Startup: use packaged MSIX startup registration. Dev/unpackaged runs show this as unavailable. Packaged builds declare `PingWindowsStartup` and expose a Settings toggle that respects Windows Startup Apps/Task Manager state.

Expected user-facing constraints:

- Protected video, DRM content, secure desktop, and some GPU overlays can produce black frames.
- Windows can show a capture border. Ping treats it as a normal privacy indicator.
- Tray icons can be hidden in Windows 11 overflow; onboarding should ask users to pin Ping if they want it always visible.

## Build

From Visual Studio Developer PowerShell:

```powershell
cd windows
dotnet test .\tests\Ping.Windows.Core.Tests\Ping.Windows.Core.Tests.csproj
dotnet test .\tests\Ping.Windows.App.Tests\Ping.Windows.App.Tests.csproj
msbuild .\PingWindows.sln /m /restore /p:Configuration=Release /p:Platform=x64
```

Release packages:

```powershell
.\scripts\build-release.ps1
```

Outputs:

```text
windows\dist\Ping-Windows-v0.3.28-x64.msix
windows\dist\Ping-Windows-v0.3.28-arm64.msix
```

Signed packages are required for external distribution. If signing is not configured, `build-release.ps1` produces unsigned packages for build validation only; users will see install/signing friction and SmartScreen may warn.

## Update Path

Windows does not use Sparkle. v1 chooses MSIX distribution as the update boundary:

- Direct distribution: App Installer feed or equivalent MSIX update channel.
- Store distribution: Microsoft Store update channel.
- Velopack remains a fallback only if MSIX update UX is not sufficient.

## Release Smoke

```powershell
.\scripts\smoke-release.ps1 -AllowUnsigned
.\scripts\smoke-release.ps1 -Install
.\tools\smoke\ScreenFaceCaptureSmoke.ps1
```

Manual checks after install:

- First-run onboarding shows OS, config, camera, microphone, screen capture, notification, hotkey, and startup rows.
- Alt+P records and sends `face_only`.
- Alt+L records and sends `screen_face`.
- Alt+Shift+L records immediately to the default room after the 300ms HUD.
- Notification click downloads from `ping-videos` and opens playback.
- History shows video and chat in one room timeline, supports text/image chat, reply previews, sender chat delete, received video hide, sender video delete, and quick emoji reactions.
- Unread room chat from another user shows one Windows notification per room, and clicking it opens History.
- Settings toggles for quick send, Windows startup, sent-copy saving, received-video saving, and recipient local-save permission persist.
- Create invite link writes the Mac-compatible `/invite/<token>` URL into the field and to the Windows clipboard.

## Cross-Platform QA Matrix

| Sender | Receiver | Mode | Expected |
|---|---|---|---|
| Windows | Mac | `face_only` | Mac notification, circular playback, seen update |
| Windows | Mac | `screen_face` | Mac expanded playback preserves `aspect_ratio` |
| Mac | Windows | `face_only` | Windows notification, circular playback, seen update |
| Mac | Windows | `screen_face` | Windows playback preserves `aspect_ratio` |
| Windows | Windows | Alt+Shift+L quick | Immediate 3-second screen+face send |
| Windows | Mac | chat image + reaction + reply | Mac shows the image attachment, reply preview, and updated reaction aggregate |
| Mac | Windows | chat image + reaction + reply | Windows shows the image attachment, reply preview, and updated reaction aggregate |
| Mac | Windows | sender chat delete | Windows removes the deleted chat from the room timeline |
| Windows | Mac | received video hide | Mac remains unaffected; Windows removes the hidden received video locally |
| Mac | Mac | existing | No regression |

Record the exact OS build, app version, sender UID, receiver UID, room ID, message ID, and Storage path for failed cases.
