# Windows Zero-Cost Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Windows client distributable at zero platform/signing cost through GitHub Releases plus self-signed MSIX sideloading.

**Architecture:** Keep MSIX as the Windows package boundary. CI signs packages with a self-signed certificate when a private PFX is available in GitHub Secrets, bundles the public `.cer` and an install helper, and publishes a release-ready sideload folder. This is not a publicly trusted production channel; it is the best free channel with explicit Windows trust friction.

**Tech Stack:** GitHub Actions, PowerShell, MSIX, SignTool/MSBuild package signing, xUnit source-contract tests.

---

### Task 1: Distribution Contract Tests

**Files:**
- Modify: `windows/tests/Ping.Windows.App.Tests/AppCoordinatorSourceTests.cs`

- [x] **Step 1: Write failing tests**

Add tests that require:
- `windows/scripts/create-sideload-certificate.ps1`
- `windows/scripts/install-ping-windows.ps1`
- `windows/scripts/package-sideload-release.ps1`
- a committed public certificate path under `windows/certs/`
- workflow import of `PING_WINDOWS_CERT_BASE64`
- workflow packaging/upload of a sideload bundle

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
dotnet test windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj -c Debug --no-restore --filter "WindowsFreeSideload"
```

Expected: failure because the scripts and workflow hooks do not exist yet.

### Task 2: PowerShell Sideload Scripts

**Files:**
- Create: `windows/scripts/create-sideload-certificate.ps1`
- Create: `windows/scripts/install-ping-windows.ps1`
- Create: `windows/scripts/package-sideload-release.ps1`

- [x] **Step 1: Implement certificate creation**

Create a Windows-only helper that generates a code-signing self-signed certificate with subject `CN=Youngmin Park`, exports `.pfx` and `.cer`, and prints the exact GitHub secret commands.

- [x] **Step 2: Implement user install helper**

Create an installer that validates the certificate, imports it into `LocalMachine\TrustedPeople`, chooses x64 or arm64 MSIX, installs via `Add-AppxPackage`, and launches Ping.

- [x] **Step 3: Implement release folder packager**

Create a packager that requires signed MSIX by default, copies both architectures, copies the public `.cer`, copies the installer helper, and writes SHA256 checksums plus a short README.

### Task 3: CI Release Wiring

**Files:**
- Modify: `.github/workflows/windows-client.yml`

- [x] **Step 1: Import signing certificate from secrets**

Decode `PING_WINDOWS_CERT_BASE64` to a PFX on Windows runners, set `PING_WINDOWS_CERT_PATH`, and keep PR builds unsigned when secrets are absent.

- [x] **Step 2: Build and package sideload bundle**

Run signed smoke when secrets are present; otherwise run unsigned validation. Upload both raw MSIX artifacts and the sideload bundle.

- [x] **Step 3: Add manual GitHub Release publishing**

For `workflow_dispatch` with `publish_release=true`, upload the sideload bundle to a GitHub Release tag using the built-in `GITHUB_TOKEN`.

### Task 4: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `windows/README.md`
- Modify: `docs/WINDOWS_APP_SETUP.md`

- [x] **Step 1: Document the recommended free route**

State that the free route is self-signed sideloading, not public-trust distribution.

- [x] **Step 2: Verify**

Run:

```bash
dotnet test windows/tests/Ping.Windows.App.Tests/Ping.Windows.App.Tests.csproj -c Debug --no-restore
dotnet test windows/tests/Ping.Windows.Core.Tests/Ping.Windows.Core.Tests.csproj -c Debug --no-restore
git diff --check
```

Expected: tests pass and whitespace checks are clean.
