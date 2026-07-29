<#
    MaxScatter -- .mzp packager

    Stages src/ into build/tmp in APPLICATION PACKAGE shape and zips it as
    dist\MaxScatter.mzp. The .mzp is only a delivery wrapper now: install.ms
    moves the staged package to
    %APPDATA%\Autodesk\ApplicationPlugins\MaxScatter, which is one install
    covering 3ds Max 2024-2027.

    The version comes from core/ns.ms (version = "x.y.z") and is stamped into
    PackageContents.xml on the way through, so ns.ms stays the single source of
    truth and the manifest cannot drift out of step with it.

    Usage:  build.bat            (from the repo root)
            powershell -ExecutionPolicy Bypass -File build\build_mzp.ps1
#>

$ErrorActionPreference = "Stop"

$repo  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $repo "src"
$stage = Join-Path $repo "build\tmp\mzp"
$dist  = Join-Path $repo "dist"

$nsFile = Join-Path $src "MaxScatter\core\ns.ms"
$ver = "0.0.0"
if ((Get-Content $nsFile -Raw) -match 'version\s*=\s*"([^"]+)"') { $ver = $Matches[1] }

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $dist  | Out-Null

# --- package shape: what install.ms expects to find beside itself
$contents = Join-Path $stage "Contents"
New-Item -ItemType Directory -Force -Path (Join-Path $contents "scripts") | Out-Null

Copy-Item (Join-Path $src "MaxScatter") (Join-Path $contents "scripts\MaxScatter") -Recurse
Copy-Item (Join-Path $src "macro")      (Join-Path $contents "macroscripts")       -Recurse
Copy-Item (Join-Path $src "cui")        (Join-Path $contents "cui")                -Recurse
Copy-Item (Join-Path $src "icons")      (Join-Path $contents "icons")              -Recurse

# --- installer entry points, at the archive root
Copy-Item (Join-Path $src "mzp.run")    $stage
Copy-Item (Join-Path $src "install.ms") $stage

# --- manifest, with the version stamped from ns.ms
$xml = Get-Content (Join-Path $src "PackageContents.xml") -Raw
$xml = $xml -replace 'AppVersion="[^"]*"',      "AppVersion=`"$ver`""
$xml = $xml -replace 'FriendlyVersion="[^"]*"', "FriendlyVersion=`"$ver`""
Set-Content (Join-Path $stage "PackageContents.xml") $xml -Encoding utf8

# --- the manifest and the menu declaration must parse
# Max reads a malformed manifest far enough to report a misleading error about
# something else, so a broken one must never leave this script. The trap is that
# a double hyphen is illegal inside an XML comment, which is exactly the comment
# style every MAXScript file here uses.
foreach ($x in @("PackageContents.xml", "Contents\cui\MaxScatter.mnx")) {
    $p = Join-Path $stage $x
    try { [xml](Get-Content $p -Raw) | Out-Null }
    catch { throw "$x is not well-formed XML: $($_.Exception.Message)" }
}

$missing = @("PackageContents.xml", "install.ms", "mzp.run",
             "Contents\scripts\MaxScatter\init.ms",
             "Contents\scripts\MaxScatter\emit\gizmo_data.ms",
             "Contents\macroscripts\MaxScatter.mcr",
             "Contents\cui\MaxScatter.mnx") |
    Where-Object { -not (Test-Path (Join-Path $stage $_)) }
if ($missing) { throw "staging incomplete, missing: $($missing -join ', ')" }

# Fixed filename: the download link and any install instructions stay valid
# across releases. The version lives in PackageContents.xml and core/ns.ms.
$mzp = Join-Path $dist "MaxScatter.mzp"
if (Test-Path $mzp) { Remove-Item $mzp -Force }

<#
    Zipped by hand instead of with Compress-Archive.

    ZIP APPNOTE 4.4.17.1: "All slashes MUST be forward slashes '/' as opposed
    to backwards slashes '\'". Compress-Archive on Windows PowerShell 5.1
    stores BACKSLASHES, so every nested entry arrives at Max's .mzp extractor
    as one flat filename ("Contents\scripts\MaxScatter\init.ms") instead of a
    tree. The package then has no Contents\ directory to find and the
    drag-and-drop install silently does nothing at all.

    CreateEntry is given the relative path with separators normalised, which is
    the only part that has to be right. Directory entries are not written: every
    extractor creates the folders implied by the entry paths.
#>
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$stageFull = (Resolve-Path $stage).Path.TrimEnd('\')
$fs = [System.IO.File]::Open($mzp, [System.IO.FileMode]::Create)
try {
    $zipArchive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in (Get-ChildItem $stageFull -Recurse -File)) {
            $rel = $f.FullName.Substring($stageFull.Length).TrimStart('\').Replace('\', '/')
            $entry = $zipArchive.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $out = $entry.Open()
            try { $bytes = [System.IO.File]::ReadAllBytes($f.FullName); $out.Write($bytes, 0, $bytes.Length) }
            finally { $out.Dispose() }
        }
    }
    finally { $zipArchive.Dispose() }
}
finally { $fs.Dispose() }

# A backslash here is the whole bug above, so never ship one.
$bad = @()
$zr = [System.IO.Compression.ZipFile]::OpenRead($mzp)
try { $bad = @($zr.Entries | Where-Object { $_.FullName -like '*\*' } | ForEach-Object { $_.FullName }) }
finally { $zr.Dispose() }
if ($bad) { throw "zip entries use backslash separators (Max cannot extract these): $($bad -join ', ')" }

$size = [math]::Round((Get-Item $mzp).Length / 1KB, 1)
"built: $mzp ($size KB)  version $ver"
"install: drag the .mzp into a 3ds Max viewport"
