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

The Windows client reads Supabase config from:

```text
%LOCALAPPDATA%\Ping\Supabase.json
```

Example:

```json
{
  "url": "https://YOUR_PROJECT_REF.supabase.co",
  "anonKey": "YOUR_SUPABASE_ANON_KEY"
}
```

This is intentionally separate from the macOS `Resources/Supabase.plist`.

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

For external distribution, sign the MSIX with a trusted certificate by passing `-PackageCertificateThumbprint` or setting `PING_WINDOWS_CERT_THUMBPRINT`. Unsigned packages are only for CI/build validation and will not install cleanly on user machines without developer/test-signing workarounds.

Smoke-check release artifacts:

```powershell
.\scripts\smoke-release.ps1 -AllowUnsigned
.\scripts\smoke-release.ps1 -Install
```

Manual hardware smoke is still required for camera, microphone, screen capture, app notifications, global hotkeys, and Mac/Windows cross-send.

The WinUI app is under `src/Ping.Windows.App`, shared product logic belongs in `src/Ping.Windows.Core`, native Windows capture work belongs in `src/Ping.Windows.NativeCapture`, and tests belong under `tests`.

## Local Verification Status

Most Windows code in this branch was authored from macOS, where `dotnet`, PowerShell, Visual Studio, Windows App SDK templates, and MSBuild C++ targets were not available. Static checks that can run on macOS have been used, but the managed tests, packaged WinUI build, native capture DLL, camera, microphone, notifications, tray, global hotkeys, MSIX install, and Mac/Windows cross-send matrix still require a Windows 11 24H2+ machine.

Before distributing a build, run the verification, build, release, and smoke commands above on Windows and record any OS-specific failures in the cross-platform QA matrix.
