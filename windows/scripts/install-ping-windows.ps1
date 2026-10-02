[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet("x64", "arm64")]
    [string]$Architecture,
    [string]$PackageDirectory = $PSScriptRoot,
    [string]$PackageBaseUrl,
    [string]$CertificatePath = (Join-Path $PSScriptRoot "Ping-Windows-Sideload.cer"),
    [switch]$NoLaunch,
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartMenuShortcut,
    [string]$IconPath,
    [string]$RegistrationRecordPath,
    [switch]$ValidateOnly,
    [switch]$NoDialogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "YoungminPark.PingWindows"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-Architecture {
    if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        return $Architecture
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
        return "arm64"
    }

    return "x64"
}

function Get-CurrentWindowsBuild {
    try {
        $currentVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $buildText = [string]$currentVersion.CurrentBuildNumber
        if (-not [string]::IsNullOrWhiteSpace($buildText)) {
            return [int]$buildText
        }
    }
    catch {
        Write-Warning "Could not read Windows build from registry. Falling back to Environment.OSVersion. $($_.Exception.Message)"
    }

    return [Environment]::OSVersion.Version.Build
}

function Assert-SupportedWindowsVersion {
    $minimumBuild = 26100
    $build = Get-CurrentWindowsBuild
    if ($build -lt $minimumBuild) {
        throw "Ping for Windows requires Windows 11 24H2 or newer (build $minimumBuild+). This PC reports build $build. Please update Windows before installing Ping."
    }
}

function Resolve-Version([string]$TargetArchitecture) {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version
    }

    if (-not [string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
        throw "Version is required when installing from PackageBaseUrl."
    }

    $candidate = Get-ChildItem -LiteralPath $PackageDirectory -Filter "Ping-Windows-v*-$TargetArchitecture.msix" |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        throw "Could not find a Ping Windows MSIX for $TargetArchitecture in $PackageDirectory."
    }

    if ($candidate.Name -notmatch '^Ping-Windows-v(?<version>.+)-[^-]+\.msix$') {
        throw "Could not infer version from $($candidate.Name)."
    }

    return $Matches.version
}

function Resolve-DependencyPackagePaths([string]$TargetArchitecture) {
    $manifestPath = Join-Path $PackageDirectory "dependencies-$TargetArchitecture.txt"
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'The bundled dependency manifest is missing.' }
    $manifestLines = @(Get-Content -LiteralPath $manifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $dependencyPaths = [System.Collections.Generic.List[string]]::new()
    $packageRoot = [System.IO.Path]::GetFullPath($PackageDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    foreach ($line in $manifestLines) {
        $trimmedLine = $line.Trim()
        $relativePath = $trimmedLine.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ($relativePath -match '^[a-zA-Z]+:|^\\|^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            throw "Dependency manifest contains an absolute path or URI, which is not allowed: $line"
        }

        if ([System.IO.Path]::GetExtension($relativePath) -notin @(".msix", ".appx")) {
            throw "Dependency manifest entry must be an .msix or .appx package: $line"
        }

        $dependencyPath = Join-Path $PackageDirectory $relativePath
        $resolvedDependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)
        if (-not $resolvedDependencyPath.StartsWith($packageRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Dependency manifest entry escapes the package directory: $line"
        }

        if (-not (Test-Path -LiteralPath $resolvedDependencyPath)) { throw "Missing bundled dependency: $resolvedDependencyPath" }

        $dependencyPaths.Add($resolvedDependencyPath)
    }

    return $dependencyPaths.ToArray()
}

function Test-SignatureMatchesCertificate($Signature, [string]$ExpectedCertificatePath) {
    if (-not $Signature.SignerCertificate) {
        return $false
    }

    $expectedCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($ExpectedCertificatePath)
    return $expectedCertificate.Thumbprint -eq '12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC' -and $Signature.SignerCertificate.Thumbprint -eq $expectedCertificate.Thumbprint
}

function Assert-PingPackageIdentity([string]$Path, [string]$TargetVersion, [string]$TargetArchitecture) {
    if ($TargetVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Ping package version.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry -or $entry.Length -gt 131072) { throw 'Package manifest is missing or invalid.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $identity = $manifest.Package.Identity
        if ($identity.Name -ne $packageName -or $identity.Publisher -ne 'CN=Youngmin Park' -or $identity.Version -ne "$TargetVersion.0" -or $identity.ProcessorArchitecture -ne $TargetArchitecture) {
            throw 'The package identity, version or architecture does not match Ping.'
        }
    } finally { $archive.Dispose() }
}

function Trust-CertificateOnly([string]$Path) {
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($Path)
    if ($certificate.Thumbprint -ne '12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC') { throw 'Unexpected Ping trust certificate.' }
    if (Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)") { return }
    $escapedPath = ([IO.Path]::GetFullPath($Path)).Replace("'", "''")
    $command = '$ErrorActionPreference = ''Stop''; $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(''__PATH__''); if ($certificate.Thumbprint -ne ''__THUMBPRINT__'') { throw ''Unexpected certificate'' }; Import-Certificate -FilePath ''__PATH__'' -CertStoreLocation ''Cert:\LocalMachine\TrustedPeople'' | Out-Null'
    $command = $command.Replace('__PATH__', $escapedPath).Replace('__THUMBPRINT__', $certificate.Thumbprint)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $hostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $trust = Start-Process -FilePath $hostPath -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($trust.ExitCode -ne 0) { throw 'Ping certificate trust was not approved or failed.' }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($PackageBaseUrl)) { throw 'This installer requires the bundled offline payload.' }

    if ([string]::IsNullOrWhiteSpace($PackageBaseUrl) -and -not (Test-Path -LiteralPath $PackageDirectory)) {
        throw "Package directory does not exist: $PackageDirectory"
    }

    if (-not (Test-Path -LiteralPath $CertificatePath)) {
        throw "Missing sideload certificate: $CertificatePath"
    }

    $targetArchitecture = Resolve-Architecture
    $Version = Resolve-Version $targetArchitecture
    $packageFileName = switch ($targetArchitecture) {
        "x64" { "Ping-Windows-v$Version-x64.msix" }
        "arm64" { "Ping-Windows-v$Version-arm64.msix" }
    }
    $packagePath = Join-Path $PackageDirectory $packageFileName

    if (-not (Test-Path -LiteralPath $packagePath)) { throw 'The bundled Ping MSIX is missing.' }
    [string[]]$dependencyPaths = @(Resolve-DependencyPackagePaths $targetArchitecture)

    Assert-PingPackageIdentity $packagePath $Version $targetArchitecture
    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    if (-not (Test-SignatureMatchesCertificate $signature $CertificatePath)) {
        throw "The MSIX signer does not match Ping-Windows-Sideload.cer. Refusing to install an unexpected package."
    }
    if ($dependencyPaths.Count -eq 0) { throw 'The bundled Windows App Runtime dependencies are missing.' }
    foreach ($dependency in $dependencyPaths) {
        $dependencySignature = Get-AuthenticodeSignature -LiteralPath $dependency
        if ($dependencySignature.Status -ne 'Valid' -or -not $dependencySignature.SignerCertificate -or $dependencySignature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
            throw 'A Windows framework dependency signature is invalid.'
        }
    }
    if ($ValidateOnly) {
        if ($signature.Status -ne 'Valid') { throw 'The package signature is not trusted on this validation machine.' }
        Write-Output 'Verified offline Ping package identity, architecture and signatures.'
        return
    }
    Assert-SupportedWindowsVersion
    if (Test-Administrator) { throw 'Run Ping Setup normally, without Run as administrator. Only certificate trust requires elevation.' }
    if ($signature.Status -in @('HashMismatch','NotSigned','NotSupportedFileFormat')) { throw 'The package signature is invalid.' }
    Write-Host 'Trusting the bundled Ping certificate if necessary...'
    Trust-CertificateOnly $CertificatePath
    if ((Get-AuthenticodeSignature -LiteralPath $packagePath).Status -ne 'Valid') {
        throw 'The Ping package signature could not be verified after certificate trust.'
    }

    Write-Host "Installing $packageFileName..."
    if ($dependencyPaths.Count -gt 0) {
        Add-AppxPackage -Path $packagePath -DependencyPath $dependencyPaths
    } else {
        Add-AppxPackage -Path $packagePath
    }

    $installed = Get-AppxPackage -Name $packageName |
        Sort-Object InstallDate -Descending |
        Select-Object -First 1
    if (-not $installed) {
        throw "Ping package did not appear in Get-AppxPackage after installation."
    }

    . (Join-Path $PSScriptRoot 'ping-user-data.ps1')
    Restore-PingUserData -LocalAppDataRoot $env:LOCALAPPDATA -PackageFamilyName $installed.PackageFamilyName
    if (-not [string]::IsNullOrWhiteSpace($RegistrationRecordPath)) {
        [IO.File]::WriteAllText($RegistrationRecordPath, $installed.PackageFamilyName)
    }

    # Icon 복사 및 단축키 구성
    $appDataPing = Join-Path $env:LOCALAPPDATA "Ping"
    if (-not (Test-Path -LiteralPath $appDataPing)) {
        New-Item -ItemType Directory -Force -Path $appDataPing | Out-Null
    }

    $localIconPath = ""
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath)) {
        $localIconPath = Join-Path $appDataPing "app.ico"
        Copy-Item -LiteralPath $IconPath -Destination $localIconPath -Force
    }

    $wshShell = New-Object -ComObject WScript.Shell

    if ($CreateDesktopShortcut) {
        Write-Host "Creating desktop shortcut..."
        $desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "Ping.lnk")
        $shortcut = $wshShell.CreateShortcut($desktopPath)
        $shortcut.TargetPath = "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
        if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
            $shortcut.IconLocation = $localIconPath
        }
        $shortcut.Save()
    }

    if ($CreateStartMenuShortcut) {
        Write-Host "Creating Start menu shortcut..."
        $programsPath = [System.Environment]::GetFolderPath("Programs")
        $pingStartMenuFolder = [System.IO.Path]::Combine($programsPath, "Ping")
        New-Item -ItemType Directory -Force -Path $pingStartMenuFolder | Out-Null
        $shortcut = $wshShell.CreateShortcut([System.IO.Path]::Combine($pingStartMenuFolder, "Ping.lnk"))
        $shortcut.TargetPath = "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
        if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
            $shortcut.IconLocation = $localIconPath
        }
        $shortcut.Save()
    }

    if (-not $NoLaunch) {
        Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\$($installed.PackageFamilyName)!App" -WindowStyle Hidden
    }

    Write-Host "Ping for Windows is installed."
}
catch {
    if ($ValidateOnly -or $NoDialogs) { Write-Error $_; exit 1 }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Ping 설치 중 오류가 발생했습니다:`n`n$($_.Exception.Message)", "Ping 설치 오류", "OK", "Error") | Out-Null
    }
    catch {
        Write-Error "Ping 설치 오류: $($_.Exception.Message)"
    }
    throw $_
}
