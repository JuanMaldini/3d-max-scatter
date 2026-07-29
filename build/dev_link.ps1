<#
    MaxScatter -- development install

    Builds a 3ds Max application package at

        %APPDATA%\Autodesk\Applicationplugins\MaxScatter

    whose contents are junctions back into this repo, so `git pull` or any edit
    updates the installed plugin with nothing to copy.

    ONE package covers 2024 through 2027. MaxScatter is pure MAXScript with no
    SDK or Qt binding, so there is nothing to build per release, and
    PackageContents.xml tells Max which versions may load it. That is why there
    is no -MaxVersion switch any more: there is nothing left to narrow.

    %APPDATA% rather than %ALLUSERSPROFILE%: Max scans both, and the per-user
    location needs no administrator rights.

    The toolbar PNGs are the one thing that still goes in per-version: Max
    resolves a macroScript `iconName:` against its usericons folder, so the
    icons are copied into each installed release's user profile.

    Usage:  powershell -ExecutionPolicy Bypass -File build\dev_link.ps1
            powershell -ExecutionPolicy Bypass -File build\dev_link.ps1 -Remove
#>
param(
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$src      = Join-Path $repoRoot "src"
$pkgRoot  = Join-Path $env:APPDATA "Autodesk\ApplicationPlugins\MaxScatter"
$contents = Join-Path $pkgRoot "Contents"
$maxRoot  = Join-Path $env:LOCALAPPDATA "Autodesk\3dsMax"

# Package subfolder  ->  repo folder it points at. Everything the plugin loads
# at runtime is a junction, so the repo is the live install.
$links = [ordered]@{
    "scripts\MaxScatter" = Join-Path $src "MaxScatter"
    "macroscripts"       = Join-Path $src "macro"
    "cui"                = Join-Path $src "cui"
    "icons"              = Join-Path $src "icons"
}

# Removes a directory that may be a junction. Recursing into a junction would
# delete the repo behind it, so a link is always unlinked non-recursively.
function Remove-Dir($path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path -Force
    if ($item.LinkType) { [System.IO.Directory]::Delete($path, $false) }
    else { Remove-Item $path -Recurse -Force }
    return $true
}

function Get-InstalledMaxVersions {
    if (-not (Test-Path $maxRoot)) { return @() }
    Get-ChildItem $maxRoot -Directory |
        Where-Object { $_.Name -match '^\d{4} - 64bit$' -and (Test-Path (Join-Path $_.FullName "ENU")) } |
        ForEach-Object { $_.Name.Substring(0, 4) } |
        Sort-Object
}

$versions = @(Get-InstalledMaxVersions)

# ---------------------------------------------------------------- legacy layout
# Before the package, MaxScatter installed into each version's user scripts with
# a scripts/startup stub to load it. Leaving those behind would load every module
# twice -- once from the stub, once from the package -- so they go first, always,
# including on a plain install.
function Remove-LegacyInstall {
    foreach ($ver in $versions) {
        $enu = Join-Path $maxRoot "$ver - 64bit\ENU"
        foreach ($p in @(
            (Join-Path $enu "scripts\startup\MaxScatter_startup.ms"),
            (Join-Path $enu "usermacros\MaxScatter.mcr")
        )) {
            if (Test-Path $p) { Remove-Item $p -Force; "  removed legacy: $p" }
        }
        $old = Join-Path $enu "scripts\MaxScatter"
        if (Remove-Dir $old) { "  removed legacy: $old" }
    }
}

# ------------------------------------------------------------------------ remove
if ($Remove) {
    "=== removing MaxScatter ==="
    foreach ($sub in $links.Keys) {
        $p = Join-Path $contents $sub
        if (Remove-Dir $p) { "  unlinked: $p" }
    }
    if (Test-Path $pkgRoot) { Remove-Item $pkgRoot -Recurse -Force; "  removed package: $pkgRoot" }
    else { "  no package at $pkgRoot" }

    Remove-LegacyInstall

    foreach ($ver in $versions) {
        $icons = Join-Path $maxRoot "$ver - 64bit\ENU\usericons"
        Get-ChildItem (Join-Path $icons "MaxScatter_*.png") -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item $_.FullName -Force; "  removed icon: $($_.Name) ($ver)" }
    }
    ""
    "Removed. Restart 3ds Max."
    exit 0
}

# ----------------------------------------------------------------------- install
foreach ($sub in $links.Keys) {
    if (-not (Test-Path $links[$sub])) { throw "source not found: $($links[$sub])" }
}
$xmlSrc = Join-Path $src "PackageContents.xml"
if (-not (Test-Path $xmlSrc)) { throw "source not found: $xmlSrc" }

"=== MaxScatter package ==="
Remove-LegacyInstall

foreach ($sub in $links.Keys) {
    $dst = Join-Path $contents $sub
    Remove-Dir $dst | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    cmd /c mklink /J "`"$dst`"" "`"$($links[$sub])`"" | Out-Null
    if (-not (Test-Path $dst)) { throw "junction failed: $dst" }
    "  Contents\$sub  ->  $($links[$sub])"
}

# The manifest is the one file that is copied: Max reads it once at startup, and
# a stale copy is the failure everyone hits, so rerun this script after editing
# src\PackageContents.xml.
Copy-Item $xmlSrc (Join-Path $pkgRoot "PackageContents.xml") -Force
"  PackageContents.xml (copied -- rerun this script if you edit it)"

# Marker so the .mzp installer refuses to copy a release over these junctions,
# which would write the release into the git working tree.
Set-Content (Join-Path $pkgRoot "DEV_LINK") @"
This package is a development link created by build\dev_link.ps1.
Contents\* are junctions into: $repoRoot
Run  build\dev_link.ps1 -Remove  before installing a .mzp release.
"@ -Encoding utf8
"  DEV_LINK marker written"

if ($versions.Count -eq 0) {
    ""
    "WARNING: no 3ds Max user profile under $maxRoot -- toolbar icons not installed."
} else {
    ""
    "=== toolbar icons ==="
    foreach ($ver in $versions) {
        $icons = Join-Path $maxRoot "$ver - 64bit\ENU\usericons"
        New-Item -ItemType Directory -Force -Path $icons | Out-Null
        Copy-Item (Join-Path $src "icons\MaxScatter_*.png") $icons -Force
        "  $ver -> $icons"
    }
}

""
"Package: $pkgRoot"
"Covers 3ds Max 2024-2027 from this one location."
"Detected on this machine: $(if ($versions) { $versions -join ', ' } else { 'none' })"
""
"RESTART 3ds Max -- a package manifest and its .mnx menu are only read at startup."
