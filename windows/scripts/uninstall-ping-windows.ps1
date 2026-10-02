[CmdletBinding()]
param(
    [string]$CertificatePath,
    [switch]$NoDialogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "YoungminPark.PingWindows"

function Remove-ShortcutIfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

try {
    . (Join-Path $PSScriptRoot 'ping-user-data.ps1')
    $packages = @(Get-AppxPackage -Name $packageName -ErrorAction Stop)

    foreach ($package in $packages) {
        if ($package.Publisher -ne 'CN=Youngmin Park') { throw 'Unexpected Ping publisher.' }
        $running = @(Get-Process -Name 'Ping.Windows.App' -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($package.InstallLocation.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
        })
        if ($running.Count -gt 0) { throw 'Exit Ping from the tray before uninstalling, then retry.' }
        Save-PingUserData -LocalAppDataRoot $env:LOCALAPPDATA -PackageFamilyName $package.PackageFamilyName | Out-Null
        Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
        Restore-PingUserData -LocalAppDataRoot $env:LOCALAPPDATA -PackageFamilyName $package.PackageFamilyName -OverwriteExisting
    }

    Remove-ShortcutIfPresent ([System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "Ping.lnk"))
    Remove-ShortcutIfPresent ([System.IO.Path]::Combine([System.Environment]::GetFolderPath("Startup"), "Ping.lnk"))

    $startMenuFolder = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Programs"), "Ping")
    Remove-ShortcutIfPresent ([System.IO.Path]::Combine($startMenuFolder, "Ping.lnk"))
    if ((Test-Path -LiteralPath $startMenuFolder) -and -not (Get-ChildItem -LiteralPath $startMenuFolder -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $startMenuFolder -Force -ErrorAction SilentlyContinue
    }

    # Shared certificate trust and runtime can serve another user's installation.
    Write-Host 'Ping removed for the current user. Accounts and settings are retained.'
}
catch {
    if ($NoDialogs) { Write-Error $_; exit 1 }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Ping 제거 중 오류가 발생했습니다:`n`n$($_.Exception.Message)", "Ping 제거 오류", "OK", "Error") | Out-Null
    }
    catch {
        Write-Error "Ping 제거 오류: $($_.Exception.Message)"
    }
    throw $_
}
