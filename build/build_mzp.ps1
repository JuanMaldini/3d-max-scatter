<#
    MaxScatter -- .mzp packager

    Stages src/ into build/tmp, zips it, renames to .mzp in dist/.
    The version is read from core/ns.ms (version = "x.y.z").

    Usage:  build.bat            (from the repo root)
            powershell -ExecutionPolicy Bypass -File build\build_mzp.ps1
#>

$ErrorActionPreference = "Stop"

$repo  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $repo "src"
$stage = Join-Path $repo "build\tmp\mzp"
$dist  = Join-Path $repo "dist"

# version from the single source of truth
$nsFile = Join-Path $src "MaxScatter\core\ns.ms"
$ver = "0.0.0"
if ((Get-Content $nsFile -Raw) -match 'version\s*=\s*"([^"]+)"') { $ver = $Matches[1] }

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $dist  | Out-Null

Copy-Item (Join-Path $src "MaxScatter")            (Join-Path $stage "MaxScatter") -Recurse
Copy-Item (Join-Path $src "macro\MaxScatter.mcr")  $stage
Copy-Item (Join-Path $src "mzp.run")               $stage
Copy-Item (Join-Path $src "install.ms")            $stage
Copy-Item (Join-Path $src "icons\MaxScatter_*.png") $stage

$zip = Join-Path $repo "build\tmp\MaxScatter.zip"
$mzp = Join-Path $dist "MaxScatter-v$ver.mzp"
if (Test-Path $zip) { Remove-Item $zip -Force }
if (Test-Path $mzp) { Remove-Item $mzp -Force }

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Move-Item $zip $mzp

$size = [math]::Round((Get-Item $mzp).Length / 1KB, 1)
"built: $mzp ($size KB)"
"install: drag the .mzp into a 3ds Max viewport"
