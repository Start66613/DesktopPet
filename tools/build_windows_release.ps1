param(
    [string]$GodotPath = "",
    [string]$InnoCompilerPath = "",
    [string]$WindowsTemplatePath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectRoot "build\windows"
$distDir = Join-Path $projectRoot "dist"
$version = "0.1.0"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) {
        $GodotPath = $godotCommand.Source
    }
    else {
        $wingetGodot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.1-stable_win64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wingetGodot) { $GodotPath = $wingetGodot.FullName }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot 4.7.1 executable was not found."
}

if ([string]::IsNullOrWhiteSpace($InnoCompilerPath)) {
    $innoCommand = Get-Command iscc -ErrorAction SilentlyContinue
    if ($innoCommand) { $InnoCompilerPath = $innoCommand.Source }
    if (-not $InnoCompilerPath) {
        $candidate = Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup *\ISCC.exe", "C:\Program Files (x86)\Inno Setup *\ISCC.exe", "C:\Program Files\Inno Setup *\ISCC.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { $InnoCompilerPath = $candidate.FullName }
    }
}
if (-not $InnoCompilerPath -or -not (Test-Path -LiteralPath $InnoCompilerPath)) {
    throw "Inno Setup compiler was not found."
}
if ([string]::IsNullOrWhiteSpace($WindowsTemplatePath)) {
    $WindowsTemplatePath = Join-Path $projectRoot ".release-cache\windows_release_x86_64.exe"
}
if (-not (Test-Path -LiteralPath $WindowsTemplatePath)) {
    throw "Godot 4.7.1 Windows release template was not found at '$WindowsTemplatePath'. Refusing to package the editor executable as an application runtime."
}
$cachedTemplatePath = Join-Path $projectRoot ".release-cache\windows_release_x86_64.exe"
if ([System.IO.Path]::GetFullPath($WindowsTemplatePath) -ne [System.IO.Path]::GetFullPath($cachedTemplatePath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cachedTemplatePath) | Out-Null
    Copy-Item -LiteralPath $WindowsTemplatePath -Destination $cachedTemplatePath -Force
}

Remove-Item -LiteralPath $buildDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $buildDir) {
    throw "Build directory is in use. Close any DesktopPet process running from '$buildDir' and retry."
}
New-Item -ItemType Directory -Force -Path $buildDir, $distDir | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_app_icon.ps1")
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_music_player_background.ps1")
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_music_session_bridge.ps1")
& $GodotPath --headless --path $projectRoot --script (Join-Path $PSScriptRoot "build_pet_sprite_frames.gd")
if ($LASTEXITCODE -ne 0) { throw "Pet SpriteFrames generation failed." }

$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$probeOutput = Join-Path $PSScriptRoot "foreground_app_probe.exe"
$probeSource = Join-Path $PSScriptRoot "foreground_app_probe.cs"
& $compiler /nologo /optimize+ /target:exe "/out:$probeOutput" $probeSource
if ($LASTEXITCODE -ne 0) { throw "Foreground app probe compilation failed." }

$exePath = Join-Path $buildDir "DesktopPet.exe"
$pckPath = Join-Path $buildDir "DesktopPet.pck"
& $GodotPath --headless --path $projectRoot --export-release "Windows Desktop" $exePath
$godotExitCode = $LASTEXITCODE
$pckFile = $null
$exeFile = $null
$lastPckLength = -1L
$stableChecks = 0
$exportDeadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $exportDeadline) {
    $pckFile = Get-Item -LiteralPath $pckPath -ErrorAction SilentlyContinue
    $exeFile = Get-Item -LiteralPath $exePath -ErrorAction SilentlyContinue
    if ($pckFile -and $pckFile.Length -ge 1MB -and $exeFile -and $exeFile.Length -ge 10MB) {
        if ($pckFile.Length -eq $lastPckLength) {
            $stableChecks++
            if ($stableChecks -ge 2) { break }
        }
        else {
            $lastPckLength = $pckFile.Length
            $stableChecks = 0
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $pckFile -or $pckFile.Length -lt 1MB -or -not $exeFile -or $exeFile.Length -lt 10MB) {
    throw "Godot Windows release export failed with exit code $godotExitCode."
}
if ($godotExitCode -ne 0) {
    Write-Warning "Godot returned exit code $godotExitCode after producing a valid Windows release. Continuing the release build."
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "foreground_app_probe.exe") -Destination $buildDir -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "music_session_bridge.exe") -Destination $buildDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "release\app_icon.ico") -Destination $buildDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "release\README.txt") -Destination $buildDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "release\THIRD_PARTY_NOTICES.txt") -Destination $buildDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "assets\fonts\OFL.txt") -Destination (Join-Path $buildDir "OFL-ZCOOL-KuaiLe.txt") -Force

# Keep Chinese release notes readable in older Windows text editors.
foreach ($textFile in @("README.txt", "THIRD_PARTY_NOTICES.txt", "OFL-ZCOOL-KuaiLe.txt")) {
    $textPath = Join-Path $buildDir $textFile
    $textContent = [System.IO.File]::ReadAllText($textPath, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($textPath, $textContent, [System.Text.UTF8Encoding]::new($true))
}

$godotLicenseUrl = "https://raw.githubusercontent.com/godotengine/godot/4.7.1-stable/LICENSE.txt"
Invoke-WebRequest -UseBasicParsing -Uri $godotLicenseUrl -OutFile (Join-Path $buildDir "LICENSE-Godot.txt")
$innoLanguagePath = Join-Path $projectRoot "release\ChineseSimplified.isl"
if (-not (Test-Path -LiteralPath $innoLanguagePath)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/ChineseSimplified.isl" -OutFile $innoLanguagePath
}

$portablePath = Join-Path $distDir "DesktopPet-$version-Portable.zip"
Remove-Item -LiteralPath $portablePath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $buildDir "*") -DestinationPath $portablePath -CompressionLevel Optimal

& $InnoCompilerPath (Join-Path $projectRoot "release\DesktopPet.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }

$setupPath = Join-Path $distDir "DesktopPet-$version-Setup.exe"
$hashes = @($setupPath, $portablePath) | ForEach-Object { Get-FileHash -Algorithm SHA256 -LiteralPath $_ }
$hashLines = $hashes | ForEach-Object { $_.Hash.ToLowerInvariant() + "  " + [System.IO.Path]::GetFileName($_.Path) }
[System.IO.File]::WriteAllLines((Join-Path $distDir "SHA256SUMS.txt"), $hashLines, [System.Text.UTF8Encoding]::new($false))

$hashes | Select-Object Path, Hash
