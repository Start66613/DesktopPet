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

# ICO files may contain PNG-compressed 256x256 images. This preserves alpha and
# avoids quality loss from the legacy bitmap icon encoder.
$pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]1)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$pngBytes.Length)
    $writer.Write([UInt32]22)
    $writer.Write($pngBytes)
    [System.IO.File]::WriteAllBytes($icoPath, $stream.ToArray())
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $icoPath
