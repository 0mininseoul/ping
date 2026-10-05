# MSIX removal can delete virtualized AppData. Keep identity and preferences in
# the current user's profile before unregistering the package.
$script:PingRetainedFiles = @(
    'SupabaseSession.json', 'SupabaseSession.json.bak', 'Supabase.json',
    'UserPreferences.json', 'MirrorPlacement.json', 'QuickSendSettings.json', 'MessengerWindowPlacement.json',
    'NotifiedMessageIds.json', 'NotifiedChatIds.json'
)

function Get-PingDataPaths([string]$LocalAppDataRoot, [string]$PackageFamilyName) {
    if ($PackageFamilyName -notmatch '^YoungminPark\.PingWindows_[A-Za-z0-9]+$') { throw 'Invalid Ping package family.' }
    $root = [IO.Path]::GetFullPath($LocalAppDataRoot).TrimEnd('\')
    $paths = @{
        Root = $root
        Physical = Join-Path $root 'Ping'
        Virtual = Join-Path $root "Packages\$PackageFamilyName\LocalCache\Local\Ping"
        Preserved = Join-Path $root "PingWindows\PreservedData\$PackageFamilyName"
    }
    foreach ($path in @($paths.Physical, $paths.Virtual, $paths.Preserved)) { Assert-PingDataPath $path $root }
    return $paths
}

function Assert-PingDataPath([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Ping data path escapes its profile root.' }
    $cursor = $full
    while ($cursor.Length -ge $Root.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Ping data path contains a link or junction.' }
        }
        if ($cursor -eq $Root) { break }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Get-PingRetainedFileNames([string[]]$SourceDirectories) {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $script:PingRetainedFiles) { $null = $names.Add($name) }
    foreach ($directory in $SourceDirectories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter 'Notified*Ids-*.json')) {
            if ($file.Name -cmatch '^Notified(Chat|Message)Ids-[a-f0-9]{64}\.json$') { $null = $names.Add($file.Name) }
        }
    }
    return @($names)
}

function Save-PingUserData([string]$LocalAppDataRoot, [string]$PackageFamilyName) {
    $paths = Get-PingDataPaths $LocalAppDataRoot $PackageFamilyName
    $snapshotId = [Guid]::NewGuid().ToString('N')
    $snapshot = Join-Path $paths.Preserved $snapshotId
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    foreach ($name in @(Get-PingRetainedFileNames @($paths.Physical, $paths.Virtual))) {
        $source = Join-Path $paths.Virtual $name
        if (-not (Test-Path -LiteralPath $source)) { $source = Join-Path $paths.Physical $name }
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Assert-PingDataPath $source $paths.Root
            Copy-Item -LiteralPath $source -Destination (Join-Path $snapshot $name)
        }
    }
    $marker = Join-Path $paths.Preserved 'current.txt'
    Assert-PingDataPath $marker $paths.Root
    $temporary = Join-Path $paths.Preserved ($snapshotId + '.tmp')
    [IO.File]::WriteAllText($temporary, $snapshotId)
    if (Test-Path -LiteralPath $marker) { [IO.File]::Replace($temporary, $marker, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $marker) }
    return $snapshot
}

function Restore-PingUserData([string]$LocalAppDataRoot, [string]$PackageFamilyName, [switch]$OverwriteExisting) {
    $paths = Get-PingDataPaths $LocalAppDataRoot $PackageFamilyName
    $marker = Join-Path $paths.Preserved 'current.txt'
    Assert-PingDataPath $marker $paths.Root
    if (-not (Test-Path -LiteralPath $marker)) { return }
    $snapshotId = [IO.File]::ReadAllText($marker).Trim()
    if ($snapshotId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid preserved Ping data snapshot.' }
    $snapshot = Join-Path $paths.Preserved $snapshotId
    Assert-PingDataPath $snapshot $paths.Root
    foreach ($name in @(Get-PingRetainedFileNames @($snapshot))) {
        $source = Join-Path $snapshot $name
        $destination = Join-Path $paths.Physical $name
        Assert-PingDataPath $source $paths.Root
        Assert-PingDataPath $destination $paths.Root
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        if (-not $OverwriteExisting -and ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath (Join-Path $paths.Virtual $name)))) { continue }
        New-Item -ItemType Directory -Path $paths.Physical -Force | Out-Null
        $temporary = Join-Path $paths.Physical ([Guid]::NewGuid().ToString('N') + '.tmp')
        Copy-Item -LiteralPath $source -Destination $temporary
        if (Test-Path -LiteralPath $destination) { [IO.File]::Replace($temporary, $destination, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $destination) }
    }
}

function Remove-PingUserData([string]$LocalAppDataRoot, [string]$PackageFamilyName) {
    $paths = Get-PingDataPaths $LocalAppDataRoot $PackageFamilyName
    foreach ($target in @($paths.Physical, $paths.Virtual, $paths.Preserved)) {
        Assert-PingDataPath $target $paths.Root
        if (-not (Test-Path -LiteralPath $target)) { continue }
        $links = @(Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($links.Count -gt 0) { throw 'Ping data contains a link or junction; automatic deletion was stopped.' }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}
