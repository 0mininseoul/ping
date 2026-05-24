# Ping Windows Client

This directory contains the Windows client workspace scaffold. It is intentionally isolated from the existing macOS app and does not change the macOS project, Sparkle setup, Swift version, deployment target, or Liquid Glass compatibility wrapper.

## Prerequisites

- Windows 11 24H2 or later.
- .NET SDK 10.x.
- Visual Studio 2026 or newer with:
  - .NET desktop development.
  - Desktop development with C++.
  - Windows App SDK tooling.
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

From this directory on Windows:

```powershell
dotnet restore .\PingWindows.sln
dotnet build .\PingWindows.sln -c Debug -p:Platform=x64
dotnet test .\PingWindows.sln -c Debug -p:Platform=x64 --no-build
dotnet build .\PingWindows.sln -c Debug -p:Platform=ARM64
dotnet test .\PingWindows.sln -c Debug -p:Platform=ARM64 --no-build
```

The WinUI app is under `src/Ping.Windows.App`, shared product logic belongs in `src/Ping.Windows.Core`, native Windows capture work belongs in `src/Ping.Windows.NativeCapture`, and tests belong under `tests`.

## Local Scaffold Status

This scaffold was created on macOS where `dotnet`, PowerShell, Visual Studio, Windows App SDK templates, and MSBuild C++ targets were not available. The solution and project files were therefore created manually and were not build-verified locally. Run the verification, build, and test commands above on Windows before starting implementation tasks that depend on generated WinUI or C++ build artifacts.
