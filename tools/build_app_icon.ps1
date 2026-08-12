$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "assets\sprites\idle\idle_01.png"
$releaseDir = Join-Path $projectRoot "release"
$pngPath = Join-Path $releaseDir "app_icon.png"
$icoPath = Join-Path $releaseDir "app_icon.ico"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$canvas = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $background = New-Object System.Drawing.Drawing2D.GraphicsPath
    $background.AddEllipse(12, 12, 232, 232)
    $graphics.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 226, 231))), $background)
    $graphics.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 226, 139, 154), 5)), $background)

    $crop = New-Object System.Drawing.Rectangle 70, 24, 116, 216
    $target = New-Object System.Drawing.Rectangle 62, 23, 132, 220
    $graphics.DrawImage($source, $target, $crop, [System.Drawing.GraphicsUnit]::Pixel)
    $canvas.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $canvas.Dispose()
    $source.Dispose()
}

# Store every Windows taskbar and shell size as a PNG-compressed ICO layer.
# The 256px layer remains the source of truth; smaller layers are pre-scaled so
# Windows does not fall back to the executable's default icon.
$iconSizes = @(16, 32, 48, 64, 128, 256)
$iconLayers = @()
$master = [System.Drawing.Bitmap]::FromFile($pngPath)
try {
    foreach ($size in $iconSizes) {
        $layer = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $layerGraphics = [System.Drawing.Graphics]::FromImage($layer)
        $layerStream = New-Object System.IO.MemoryStream
        try {
            $layerGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $layerGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $layerGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $layerGraphics.Clear([System.Drawing.Color]::Transparent)
            $layerGraphics.DrawImage($master, 0, 0, $size, $size)
            $layer.Save($layerStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $iconLayers += ,$layerStream.ToArray()
        }
        finally {
            $layerStream.Dispose()
            $layerGraphics.Dispose()
            $layer.Dispose()
        }
    }
}
finally {
    $master.Dispose()
}

$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$iconLayers.Count)

    $dataOffset = 6 + 16 * $iconLayers.Count
    for ($index = 0; $index -lt $iconLayers.Count; $index++) {
        $size = $iconSizes[$index]
        $layerBytes = $iconLayers[$index]
        $writer.Write([Byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([Byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([Byte]0)
        $writer.Write([Byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$layerBytes.Length)
        $writer.Write([UInt32]$dataOffset)
        $dataOffset += $layerBytes.Length
    }
    foreach ($layerBytes in $iconLayers) {
        $writer.Write($layerBytes)
    }
    [System.IO.File]::WriteAllBytes($icoPath, $stream.ToArray())
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $icoPath
