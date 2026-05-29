# Ping Windows Client

This directory contains the native Windows client workspace. It is intentionally isolated from the existing macOS app and does not change the macOS project, Sparkle setup, Swift version, deployment target, or Liquid Glass compatibility wrapper.

## Prerequisites

- Windows 11 24H2 or later.
- .NET SDK 10.x.
- Visual Studio with:
  - .NET desktop development.
  - Desktop development with C++.
  - MSVC v143 build tools, because `Ping.Windows.NativeCapture.vcxproj` currently targets `PlatformToolset` `v143`.
  - Windows App SDK tooling for the pinned `Microsoft.WindowsAppSDK` 2.1.3 stable package.
- Windows SDK 10.0.26100.0 or newer.

## Environment Verification

Run these commands in PowerShell on Windows:

```powershell
dotnet --version
dotnet --list-sdks
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Workload.ManagedDesktop Microsoft.VisualStudio.Workload.NativeDesktop -property installationVersion
```

Expected results:

- `dotnet --version` starts with `10`.
- `dotnet --list-sdks` includes a 10.x SDK.
- `vswhere` prints a Visual Studio installation version with the .NET desktop and C++ desktop workloads installed.
- Visual Studio Installer also shows Windows App SDK tooling installed.

## Build And Test

Use Visual Studio Developer PowerShell for the full mixed C# and C++ solution:

```powershell
cd windows
msbuild .\PingWindows.sln /restore /m /p:Configuration=Debug /p:Platform=x64
msbuild .\PingWindows.sln /restore /m /p:Configuration=Debug /p:Platform=ARM64
msbuild .\PingWindows.sln /m /p:Configuration=Release /p:Platform=x64
msbuild .\PingWindows.sln /m /p:Configuration=Release /p:Platform=ARM64
```

Managed-only test projects can also be run with the .NET SDK:

```powershell
cd windows
dotnet test .\tests\Ping.Windows.Core.Tests\Ping.Windows.Core.Tests.csproj -c Debug
dotnet test .\tests\Ping.Windows.App.Tests\Ping.Windows.App.Tests.csproj -c Debug
```

## Runtime Configuration

The Windows client resolves Supabase config via `SupabaseConfigLocator`, in order:

1. User override: `%LOCALAPPDATA%\Ping\Supabase.json` (if present)
2. Bundled default: `Supabase.json` next to the installed executable

Release MSIX packages **bundle** `Supabase.json` (shared backend URL + public anon
key) so a freshly installed Ping works with zero manual setup — mirroring how the
macOS app bundles `Resources/Supabase.plist`. The bundled file is git-ignored and
written by CI from the `PING_SUPABASE_URL` / `PING_SUPABASE_ANON_KEY` secrets; see
`Supabase.example.json` for the format. For local dev (no secret), the build still
succeeds and the app falls back to the user override.

Example (`Supabase.json`):

```json
{
  "url": "https://YOUR_PROJECT_REF.supabase.co",
  "anonKey": "YOUR_SUPABASE_ANON_KEY"
}
```

## Release Package

Build release MSIX packages on Windows:

```powershell
.\scripts\build-release.ps1
```

Expected outputs:

```text
windows\dist\Ping-Windows-v0.3.28-x64.msix
windows\dist\Ping-Windows-v0.3.28-arm64.msix
```

For self-hosted distribution, Ping uses a self-signed MSIX sideload package plus a small web setup EXE:

```powershell
.\scripts\create-sideload-certificate.ps1
.\scripts\build-release.ps1
.\scripts\package-sideload-release.ps1
.\scripts\build-installer.ps1
```

CI reads `PING_WINDOWS_CERT_BASE64` and `PING_WINDOWS_CERT_PASSWORD` from GitHub Secrets, imports the PFX into the current user's certificate store, and signs by certificate thumbprint. When those secrets exist, the workflow signs the MSIX packages, copies the public `windows\certs\Ping-Windows-Sideload.cer`, writes `windows\dist\Ping-Windows-v0.3.28-sideload.zip`, and builds `windows\dist\PingSetup-v0.3.28.exe`. The setup EXE downloads the correct MSIX from `https://ping0min.vercel.app/downloads/windows/` during installation.

General users install the distribution by running:

```text
PingSetup-v0.3.28.exe
```

Because this is a self-hosted installer rather than a public-trust signed EXE, Windows SmartScreen can warn on first run. The user should choose `More info` and `Run anyway` if they trust this Ping release.

The sideload zip remains available as a fallback/debug path:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ping-windows.ps1
```

Both installer paths import `Ping-Windows-Sideload.cer` into `Cert:\LocalMachine\TrustedPeople`, pick x64 or arm64 from `ProcessArchitecture`, install the MSIX, and launch Ping. This is the best self-hosted route, but it is still sideloading under the hood. Microsoft Store, Azure Artifact Signing, or an OV code-signing certificate are required for broad public-trust installation.

Unsigned packages are only for CI/build validation and will not install cleanly on user machines without developer/test-signing workarounds.

Smoke-check release artifacts:

```powershell
.\scripts\smoke-release.ps1 -AllowUnsigned
.\scripts\smoke-release.ps1 -Install
```

Manual hardware smoke is still required for camera, microphone, screen capture, app notifications, global hotkeys, and Mac/Windows cross-send.
History smoke should also cover room text chat, `ping-media` image attachments, reaction toggles, and unread chat notifications across Windows and macOS.

The WinUI app is under `src/Ping.Windows.App`, shared product logic belongs in `src/Ping.Windows.Core`, native Windows capture work belongs in `src/Ping.Windows.NativeCapture`, and tests belong under `tests`.

## Local Verification Status

Managed portable tests can run on macOS with .NET 10 and should be kept green there:

```bash
dotnet test windows/tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj -c Debug
dotnet test windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj -c Debug
```

The packaged WinUI build still requires Windows because `Ping.Windows.NativeCapture.vcxproj` imports Visual Studio C++ targets. On macOS, `dotnet build windows/src/Ping.Windows.App/Ping.Windows.App.csproj -p:EnableWindowsTargeting=true` is expected to stop at `Microsoft.Cpp.Default.props` / `VCTargetsPath`.

The packaged WinUI build, native capture DLL, camera, microphone, notifications, tray, global hotkeys, MSIX install, and Mac/Windows cross-send matrix still require a Windows 11 24H2+ machine.

Before distributing a build, run the verification, build, release, and smoke commands above on Windows and record any OS-specific failures in the cross-platform QA matrix.
