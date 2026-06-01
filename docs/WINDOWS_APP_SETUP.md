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

**일반 사용자는 별도 설정이 필요 없습니다.** 배포되는 MSIX에는 공유 백엔드의
`Supabase.json`(공개 URL + 공개 anon 키)이 함께 들어 있어 설치 직후 바로 동작합니다.
CI가 빌드 시 `PING_SUPABASE_URL` / `PING_SUPABASE_ANON_KEY` 시크릿으로 이 파일을
생성해 패키지에 포함합니다(`SupabaseConfigLocator` 참조).

다른 백엔드를 가리키려는 파워유저/개발자는 아래 위치에 오버라이드 파일을 두면
동봉본보다 우선 적용됩니다:

```text
%LOCALAPPDATA%\Ping\Supabase.json
```

```json
{
  "url": "https://YOUR_PROJECT_REF.supabase.co",
  "anonKey": "YOUR_SUPABASE_ANON_KEY"
}
```

설정 탐색 우선순위: ① `%LOCALAPPDATA%\Ping\Supabase.json`(존재 시) →
② 앱 설치 폴더 동봉본.

The Windows client stores its anonymous session separately at:

```text
%LOCALAPPDATA%\Ping\SupabaseSession.json
```

Windows and Mac installations are separate anonymous identities. Connect them through room invitations or invite links.

## Hotkeys

| macOS | Windows | Behavior |
|---|---|---|
| Option+P | Alt+P | Face-only mirror, Enter records, review Enter sends |
| Option+L | Alt+L | Screen+face mirror, Enter records, review Enter sends |
| none | Alt+Shift+L | Quick screen+face send to default room |
| Option+O | Alt+O | Room history |

If a hotkey is already used by another app, onboarding/settings show it as conflicted and Settings > Hotkeys lets the user apply a different Ctrl/Alt/Shift/Win + key binding. Ping saves the new binding only after Windows accepts the global hotkey registration.

## Onboarding Checks

1. OS support: show unsupported warning outside Windows 11 24H2+ and disable screen+face quick send when required APIs or Supabase config are unavailable.
2. Supabase config: resolve config via `SupabaseConfigLocator` (user override at `%LOCALAPPDATA%\Ping\Supabase.json`, otherwise the config bundled in the installed package). Because release packages bundle the config, this check passes out of the box for general users.
3. Admin/elevated state: app notifications are not supported for elevated apps, so users should restart Ping normally.
4. Camera: check packaged webcam capability and initialize MediaCapture.
5. Microphone: initialize audio capture; v1 does not provide silent-video fallback.
6. Screen capture: check `GraphicsCaptureSession.IsSupported()` and run the native one-frame monitor self-test.
7. Notifications: register Windows App SDK notifications and show a local test notification.
8. Hotkeys: register Alt+P, Alt+L, Alt+Shift+L, and Alt+O with Win32 `RegisterHotKey`.
9. Startup: use packaged MSIX startup registration. Dev/unpackaged runs show this as unavailable. Packaged builds declare `PingWindowsStartup` and expose a Settings toggle that respects Windows Startup Apps/Task Manager state.

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
windows\dist\Ping-Windows-v0.3.29-x64.msix
windows\dist\Ping-Windows-v0.3.29-arm64.msix
```

Signed packages are required for external distribution. If signing is not configured, `build-release.ps1` produces unsigned packages for build validation only; users will see install/signing friction and SmartScreen may warn.

### Zero-Cost EXE Sideload Distribution

The recommended no-cost self-hosted channel is the public landing page plus a single `PingSetup-v0.3.29.exe` installer. The EXE bundles `Ping-Windows-Sideload.cer` and installer scripts, then downloads the signed x64 or ARM64 MSIX package plus Windows App Runtime dependency packages from `https://0minping.vercel.app/downloads/windows/` during installation. It avoids paid public code-signing, but Windows SmartScreen can still warn because the outer EXE is not publicly trusted.

Maintainer setup on Windows:

```powershell
.\windows\scripts\create-sideload-certificate.ps1
Get-Content -Raw .\windows\certs\private\Ping-Windows-Sideload.pfx.base64.txt | gh secret set PING_WINDOWS_CERT_BASE64
gh secret set PING_WINDOWS_CERT_PASSWORD
```

Only commit `windows\certs\Ping-Windows-Sideload.cer`. Do not commit `.pfx`, `.p12`, base64 payloads, or passwords.

The GitHub Actions workflow imports the PFX secret into `Cert:\CurrentUser\My`, signs both MSIX packages by certificate thumbprint, builds `windows\dist\Ping-Windows-v0.3.29-sideload.zip`, and builds the small web installer `windows\dist\PingSetup-v0.3.29.exe` with Inno Setup. The workflow uploads a `ping-windows-web-downloads` artifact containing the setup EXE, both MSIX payloads, dependency manifests/packages, and the public certificate so those files can be published under `web/public/downloads/windows/`.

End-user install:

```text
Download PingSetup-v0.3.29.exe from the landing page, run it, accept SmartScreen/UAC prompts, and let the installer finish.
```

Fallback/debug install from the unzipped release folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ping-windows.ps1
```

Both installer paths import `Ping-Windows-Sideload.cer` into `Cert:\LocalMachine\TrustedPeople`, verify the MSIX signature, install the correct x64 or arm64 package, and launch Ping.

## Update Path

Windows does not use Sparkle. v1 chooses MSIX distribution as the update boundary:

- Free direct distribution: public landing-page setup EXE. Users install a small setup EXE that trusts the Ping sideload certificate and downloads the signed MSIX payload plus dependencies from the public downloads directory.
- Direct production distribution: App Installer feed or equivalent MSIX update channel with a public-trust signing route.
- Store distribution: Microsoft Store update channel.
- Velopack remains a fallback only if MSIX update UX is not sufficient.

## Release Smoke

```powershell
.\scripts\smoke-release.ps1 -AllowUnsigned
.\scripts\smoke-release.ps1 -Install
.\tools\smoke\ScreenFaceCaptureSmoke.ps1
```

Release smoke checks the MSIX identity, architecture, signature status, and bundled `Ping.Windows.NativeCapture.dll`. Native capture smoke records a 3-second screen+face MP4 and verifies duration, 30fps video, audio presence, and basic resolution before manual playback checks.

Manual checks after install:

- First-run onboarding shows OS, config, camera, microphone, screen capture, notification, hotkey, and startup rows.
- Alt+P records `face_only`, shows review playback, then review Enter sends.
- Alt+L records `screen_face`, shows review playback, then review Enter sends.
- Alt+Shift+L records immediately to the default room after the 300ms HUD.
- Notification click downloads from `ping-videos` and opens playback at the sender position. After the first play ends, Enter replays, Esc closes, and idle playback fades out after about 10 seconds.
- History shows video and chat in one room timeline, auto-refreshes the selected room while open, and supports direct video Play/double-click playback, text/image chat, Enter-to-send with Shift+Enter newline, reply previews, sender chat delete, received video hide, sender video delete, and quick emoji reactions.
- Unread room chat from another user shows one Windows notification per room, and clicking it opens History with the notified chat selected.
- Settings can edit and save the Supabase profile nickname used for room actions and sent message labels.
- Rooms can search users by profile nickname and invite the selected user, matching the Mac room setup flow.
- Settings toggles for quick send, Windows startup, sent-copy saving, received-video saving, recipient local-save permission, and 30-day local archive deletion persist.
- Settings > Storage shows the local archive path under `Documents\Ping`, opens it in Explorer, and creates `sent`/`received` folders before opening.
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
| Mac | Windows | chat image + reaction + reply | Windows notification opens the room with the notified chat selected; Windows shows the image attachment, reply preview, and updated reaction aggregate |
| Mac | Windows | sender chat delete | Windows removes the deleted chat from the room timeline |
| Windows | Mac | received video hide | Mac remains unaffected; Windows removes the hidden received video locally |
| Mac | Mac | existing | No regression |

Record the exact OS build, app version, sender UID, receiver UID, room ID, message ID, and Storage path for failed cases.
