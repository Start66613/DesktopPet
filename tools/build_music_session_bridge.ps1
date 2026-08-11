$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot "music_session_bridge.cs"
$output = Join-Path $PSScriptRoot "music_session_bridge.exe"
$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$windowsMetadata = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\UnionMetadata" -Directory |
    Where-Object { $_.Name -ne "Facade" } |
    Sort-Object Name |
    ForEach-Object { Join-Path $_.FullName "Windows.winmd" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
$windowsRuntime = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.Runtime.WindowsRuntime.dll"
$systemRuntime = Get-ChildItem "C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework" -Recurse -Filter System.Runtime.dll |
    Where-Object { $_.DirectoryName -like "*Facades*" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

foreach ($required in @($compiler, $source, $windowsMetadata, $windowsRuntime, $systemRuntime)) {
    if (-not $required -or -not (Test-Path -LiteralPath $required)) {
        throw "Missing bridge build dependency: $required"
    }
}

& $compiler /nologo /optimize+ /target:exe /out:$output /reference:$windowsMetadata /reference:$windowsRuntime /reference:$systemRuntime /reference:System.Web.Extensions.dll $source
if ($LASTEXITCODE -ne 0) {
    throw "music_session_bridge compilation failed with exit code $LASTEXITCODE"
}

Write-Output "Built $output"
