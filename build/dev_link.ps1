<#
    MaxScatter -- development install

    Junctions the repo source into Max's user scripts folder so `git pull`
    updates the installed plugin with no copying, and drops the macroscript
    into usermacros.

    Usage:  powershell -ExecutionPolicy Bypass -File build\dev_link.ps1
            powershell -ExecutionPolicy Bypass -File build\dev_link.ps1 -MaxVersion 2025
            powershell -ExecutionPolicy Bypass -File build\dev_link.ps1 -Remove
#>
param(
    [string]$MaxVersion = "2024",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$repoSrc = Join-Path (Split-Path $PSScriptRoot -Parent) "src\MaxScatter"
$macroSrc = Join-Path (Split-Path $PSScriptRoot -Parent) "src\macro\MaxScatter.mcr"
$enu = Join-Path $env:LOCALAPPDATA "Autodesk\3dsMax\$MaxVersion - 64bit\ENU"
$link = Join-Path $enu "scripts\MaxScatter"
$macroDst = Join-Path $enu "usermacros\MaxScatter.mcr"
$startupDst = Join-Path $enu "scripts\startup\MaxScatter_startup.ms"

if (-not (Test-Path $enu)) { throw "3ds Max $MaxVersion user folder not found: $enu" }

if ($Remove) {
    if (Test-Path $link) {
        # Remove the junction only -- never recurse into it, that would delete the repo
        [System.IO.Directory]::Delete($link, $false)
        "removed junction: $link"
    } else { "no junction at $link" }
    if (Test-Path $macroDst) { Remove-Item $macroDst -Force; "removed macro: $macroDst" }
    if (Test-Path $startupDst) { Remove-Item $startupDst -Force; "removed startup stub: $startupDst" }
    return
}

if (-not (Test-Path $repoSrc)) { throw "source not found: $repoSrc" }

if (Test-Path $link) {
    [System.IO.Directory]::Delete($link, $false)
    "replaced existing junction"
}

cmd /c mklink /J "`"$link`"" "`"$repoSrc`"" | Out-Null
if (-not (Test-Path $link)) { throw "junction failed: $link" }
"junction: $link  ->  $repoSrc"

New-Item -ItemType Directory -Force -Path (Split-Path $macroDst) | Out-Null
Copy-Item $macroSrc $macroDst -Force
"macro:    $macroDst"

# Scripted plugin classes must exist BEFORE a saved scene that uses them is
# opened, or its objects load as Missing Plugin -- hence a startup stub.
New-Item -ItemType Directory -Force -Path (Split-Path $startupDst) | Out-Null
@'
-- MaxScatter: load the plugin class before any scene opens
(
    local p = (getDir #userScripts) + "\\MaxScatter\\init.ms"
    if doesFileExist p do fileIn p
)
'@ | Out-File $startupDst -Encoding ascii
"startup:  $startupDst"

""
"Next: in 3ds Max run   fileIn @`"$link\init.ms`"   then MaxScatter_openUI()"
"Toolbar button: Customize > Customize UI > Toolbars > Category 'MaxScatter'"
