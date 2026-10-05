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
    $accountDirectory = $paths.Physical
    if ((Test-Path -LiteralPath (Join-Path $paths.Virtual 'SupabaseSession.json')) -or
        (Test-Path -LiteralPath (Join-Path $paths.Virtual 'SupabaseSession.json.bak'))) { $accountDirectory = $paths.Virtual }
    foreach ($name in @(Get-PingRetainedFileNames @($paths.Physical, $paths.Virtual))) {
        if ($name -in @('SupabaseSession.json', 'SupabaseSession.json.bak')) {
            $source = Join-Path $accountDirectory $name
            if ($name -eq 'SupabaseSession.json' -and -not (Test-Path -LiteralPath $source)) { $source += '.bak' }
        } else {
            $source = Join-Path $paths.Virtual $name
            if (-not (Test-Path -LiteralPath $source)) { $source = Join-Path $paths.Physical $name }
        }
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
    function Restore-PreservedFile([string]$SourceName, [string]$DestinationName) {
        $source = Join-Path $snapshot $SourceName
        $destination = Join-Path $paths.Physical $DestinationName
        Assert-PingDataPath $source $paths.Root
        Assert-PingDataPath $destination $paths.Root
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
        New-Item -ItemType Directory -Path $paths.Physical -Force | Out-Null
        $temporary = Join-Path $paths.Physical ([Guid]::NewGuid().ToString('N') + '.tmp')
        Assert-PingDataPath $temporary $paths.Root
        try {
            Copy-Item -LiteralPath $source -Destination $temporary
            if (Test-Path -LiteralPath $destination) { [IO.File]::Replace($temporary, $destination, [NullString]::Value) }
            else { [IO.File]::Move($temporary, $destination) }
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    }
    $existingAccount = $false
    foreach ($directory in @($paths.Physical, $paths.Virtual)) {
        foreach ($name in @('SupabaseSession.json', 'SupabaseSession.json.bak')) {
            if (Test-Path -LiteralPath (Join-Path $directory $name)) { $existingAccount = $true }
        }
    }
    if ($OverwriteExisting -or -not $existingAccount) {
        $primary = Join-Path $snapshot 'SupabaseSession.json'
        $backup = Join-Path $snapshot 'SupabaseSession.json.bak'
        if ((Test-Path -LiteralPath $primary -PathType Leaf) -or (Test-Path -LiteralPath $backup -PathType Leaf)) {
            if (Test-Path -LiteralPath $primary -PathType Leaf) { Restore-PreservedFile 'SupabaseSession.json' 'SupabaseSession.json' }
            else { Restore-PreservedFile 'SupabaseSession.json.bak' 'SupabaseSession.json' }
            if (Test-Path -LiteralPath $backup -PathType Leaf) { Restore-PreservedFile 'SupabaseSession.json.bak' 'SupabaseSession.json.bak' }
            elseif ($OverwriteExisting) {
                $staleBackup = Join-Path $paths.Physical 'SupabaseSession.json.bak'
                Assert-PingDataPath $staleBackup $paths.Root
                if (Test-Path -LiteralPath $staleBackup -PathType Leaf) { Remove-Item -LiteralPath $staleBackup }
            }
        }
    }
    foreach ($name in @(Get-PingRetainedFileNames @($snapshot))) {
        if ($name -in @('SupabaseSession.json', 'SupabaseSession.json.bak')) { continue }
        if (-not $OverwriteExisting -and ((Test-Path -LiteralPath (Join-Path $paths.Physical $name)) -or (Test-Path -LiteralPath (Join-Path $paths.Virtual $name)))) { continue }
        Restore-PreservedFile $name $name
    }
}

function Initialize-PingPackagedData([string]$LocalAppDataRoot, [string]$PackageFamilyName) {
    $paths = Get-PingDataPaths $LocalAppDataRoot $PackageFamilyName
    function Copy-MissingPackagedFile([string]$source, [string]$destination) {
        Assert-PingDataPath $source $paths.Root
        Assert-PingDataPath $destination $paths.Root
        if ((Test-Path -LiteralPath $destination) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
        New-Item -ItemType Directory -Path $paths.Virtual -Force | Out-Null
        $temporary = Join-Path $paths.Virtual ([Guid]::NewGuid().ToString('N') + '.tmp')
        Assert-PingDataPath $temporary $paths.Root
        try {
            Copy-Item -LiteralPath $source -Destination $temporary
            # Never replace data if the app created it while setup was running.
            [IO.File]::Move($temporary, $destination)
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    }

    $session = Join-Path $paths.Virtual 'SupabaseSession.json'
    $backup = $session + '.bak'
    Assert-PingDataPath $session $paths.Root
    Assert-PingDataPath $backup $paths.Root
    if (-not (Test-Path -LiteralPath $session)) {
        if (Test-Path -LiteralPath $backup) { Copy-MissingPackagedFile $backup $session }
        else {
            $legacy = Join-Path $paths.Physical 'SupabaseSession.json'
            $legacyBackup = $legacy + '.bak'
            Assert-PingDataPath $legacy $paths.Root
            if (Test-Path -LiteralPath $legacy) { Copy-MissingPackagedFile $legacy $session }
            else { Copy-MissingPackagedFile $legacyBackup $session }
            Copy-MissingPackagedFile $legacyBackup $backup
        }
    }
    # The active package account and its backup belong to one refresh chain.
    foreach ($name in @(Get-PingRetainedFileNames @($paths.Physical))) {
        if ($name -in @('SupabaseSession.json', 'SupabaseSession.json.bak')) { continue }
        Copy-MissingPackagedFile (Join-Path $paths.Physical $name) (Join-Path $paths.Virtual $name)
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
