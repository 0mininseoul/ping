param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$pingRepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pingSourcePath = Join-Path $pingRepositoryRoot 'Ping/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png'
$pingAssetsPath = Join-Path $pingRepositoryRoot 'windows/src/Ping.Windows.App/Assets'
$pingSource = [System.Drawing.Image]::FromFile($pingSourcePath)

# Format the existing macOS artwork for Windows; keep its original transparency and composition.
function Get-PingIconPng([int]$Size) {
    $pingBitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pingGraphics = [System.Drawing.Graphics]::FromImage($pingBitmap)
    $pingStream = [System.IO.MemoryStream]::new()
    try {
        $pingGraphics.Clear([System.Drawing.Color]::Transparent)
        $pingGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $pingGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $pingGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $pingGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $pingAttributes = [System.Drawing.Imaging.ImageAttributes]::new()
        try {
            $pingAttributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $pingGraphics.DrawImage($pingSource, [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
                0, 0, $pingSource.Width, $pingSource.Height, [System.Drawing.GraphicsUnit]::Pixel, $pingAttributes)
        } finally { $pingAttributes.Dispose() }
        $pingBitmap.Save($pingStream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,($pingStream.ToArray())
    } finally { $pingStream.Dispose(); $pingGraphics.Dispose(); $pingBitmap.Dispose() }
}

try {
    foreach ($pingEntry in @(
        @{ Name = 'PingAppList'; Size = 44 },
        @{ Name = 'PingTile'; Size = 150 },
        @{ Name = 'PingStoreLogo'; Size = 50 }
    )) {
        [System.IO.File]::WriteAllBytes((Join-Path $pingAssetsPath "$($pingEntry.Name).png"), (Get-PingIconPng $pingEntry.Size))
        foreach ($pingScale in @(100, 125, 150, 200, 400)) {
            $pingSize = [int][Math]::Round($pingEntry.Size * $pingScale / 100.0, [MidpointRounding]::AwayFromZero)
            [System.IO.File]::WriteAllBytes((Join-Path $pingAssetsPath "$($pingEntry.Name).scale-$pingScale.png"), (Get-PingIconPng $pingSize))
        }
    }
    $pingIconSizes = @(16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256)
    $pingFrames = @()
    foreach ($pingSize in $pingIconSizes) {
        $pingPng = Get-PingIconPng $pingSize
        foreach ($pingSuffix in @('', '_altform-unplated', '_altform-lightunplated')) {
            [System.IO.File]::WriteAllBytes((Join-Path $pingAssetsPath "PingAppList.targetsize-$pingSize$pingSuffix.png"), $pingPng)
        }
        $pingFrames += @{ Size = $pingSize; Data = $pingPng }
    }
    $pingIcoStream = [System.IO.MemoryStream]::new()
    $pingWriter = [System.IO.BinaryWriter]::new($pingIcoStream)
    try {
        $pingWriter.Write([UInt16]0); $pingWriter.Write([UInt16]1); $pingWriter.Write([UInt16]$pingFrames.Count)
        $pingOffset = 6 + 16 * $pingFrames.Count
        foreach ($pingFrame in $pingFrames) {
            $pingDimension = if ($pingFrame.Size -eq 256) { 0 } else { $pingFrame.Size }
            $pingWriter.Write([byte]$pingDimension); $pingWriter.Write([byte]$pingDimension)
            $pingWriter.Write([byte]0); $pingWriter.Write([byte]0)
            $pingWriter.Write([UInt16]1); $pingWriter.Write([UInt16]32)
            $pingWriter.Write([UInt32]$pingFrame.Data.Length); $pingWriter.Write([UInt32]$pingOffset)
            $pingOffset += $pingFrame.Data.Length
        }
        foreach ($pingFrame in $pingFrames) { $pingWriter.Write([byte[]]$pingFrame.Data) }
        $pingWriter.Flush()
        $pingIco = $pingIcoStream.ToArray()
        [System.IO.File]::WriteAllBytes((Join-Path $pingAssetsPath 'Ping.ico'), $pingIco)
        [System.IO.File]::WriteAllBytes((Join-Path $pingRepositoryRoot 'windows/installer/app.ico'), $pingIco)
    } finally { $pingWriter.Dispose(); $pingIcoStream.Dispose() }
} finally { $pingSource.Dispose() }

Write-Output 'Created Windows shell resources from the existing macOS icon. No application checks were run.'
