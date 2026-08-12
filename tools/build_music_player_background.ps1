$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $PSScriptRoot "..\assets\music\runtime\ui\player_panel.png"
$outputPath = Join-Path $PSScriptRoot "..\assets\music\runtime\ui\player_panel_clean.png"
$source = [System.Drawing.Bitmap]::FromFile((Resolve-Path $sourcePath))
$output = New-Object System.Drawing.Bitmap($source)

try {
    # The generated panel has seven transport controls and a static progress bar
    # baked into it. Rebuild that area from a clean interior sample so Godot can
    # place real, stateful controls over the artwork.
    $left = 220
    $right = 1394
    $top = 660
    $bottom = 906
    $sampleLeft = 700
    $sampleTop = 555
    $sampleWidth = 690
    $sampleHeight = 88

    for ($y = $top; $y -le $bottom; $y++) {
        $sampleY = $sampleTop + (($y - $top) % $sampleHeight)
        for ($x = $left; $x -le $right; $x++) {
            $sampleX = $sampleLeft + (($x - $left) % $sampleWidth)
            $output.SetPixel($x, $y, $source.GetPixel($sampleX, $sampleY))
        }
    }

    # Remove the album frame's baked-in bow and roses. The runtime draws these
    # as a foreground layer over the live cover so they can occlude it cleanly.
    $decorationLeft = 136
    $decorationRight = 570
    $decorationTop = 486
    $decorationBottom = 670
    $decorationSampleLeft = 620
    for ($y = $decorationTop; $y -le $decorationBottom; $y++) {
        for ($x = $decorationLeft; $x -le $decorationRight; $x++) {
            $sampleX = $decorationSampleLeft + ($x - $decorationLeft)
            $output.SetPixel($x, $y, $source.GetPixel($sampleX, $y))
        }
    }

    $output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $outputPath
}
finally {
    $output.Dispose()
    $source.Dispose()
}
