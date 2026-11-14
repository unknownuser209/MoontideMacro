# Builds dist\MoontideMacro-v<version>.zip from the tracked program files.
# Run from anywhere:  powershell -NoProfile -File tools\make_release.ps1
# It only writes under dist\ : it does NOT push, tag or publish anything.
# The version is Brand.Version in lib\Brand.ahk (bump it before building).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$brand = Get-Content -Raw (Join-Path $root 'lib\Brand.ahk')
if ($brand -notmatch 'static Version := "([^"]+)"') { throw 'Brand.Version not found in lib\Brand.ahk' }
$version = $Matches[1]

# Never shipped: settings, per-user state, logs, dev tooling, tests and docs.
# The tracked data defaults ARE shipped (routes recorded with VIP, the empty
# calibration + the 2560x1440 preset, default quests / merchants / potions /
# biomes): a fresh install needs them, and the updater never overwrites a
# user's own copy (Updater.Protected).
$exclude = @(
    '^settings\.ini$', '^logs/', '^exports/', '^backup/', '^dist/', '^update_tmp/',
    '^\.harness/', '^\.claude/', '^\.superpowers/', '^tests/', '^docs/',
    '^\.gitattributes$', '^\.gitignore$',
    '^data/auras_had\.txt$', '^data/[^/]*state[^/]*\.json$',
    '^data/(potion_usage\.json|last_biome\.txt|minions_routes\.json|auras_learnt\.json)$',
    '^data/(stats\.json|summary_last\.txt|schedule_state\.txt|update_skip\.txt|whatsnew\.json)$'
)

$files = @(git ls-files) | Where-Object {
    $f = $_
    -not ($exclude | Where-Object { $f -match $_ })
}
if ($files -notcontains 'Vesper.ahk') { throw 'Vesper.ahk is not tracked; refusing to build' }

# Build from the COMMITTED files (git archive HEAD), never the working copy:
# the owner's local settings / data edits must not leak into a release.
$src = Join-Path ([System.IO.Path]::GetTempPath()) ("moontide_release_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $src | Out-Null
$tar = Join-Path $src 'head.tar'
git archive --format=tar -o $tar HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
& (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $tar -C $src   # Windows tar (Git Bash puts its own tar first)
if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
Remove-Item $tar

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "MoontideMacro-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$arc = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($f in $files) {
        # forward slashes inside the zip, files at the zip root (Vesper.ahk on top)
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $arc, (Join-Path $src $f), $f, [System.IO.Compression.CompressionLevel]::Optimal)
    }
    # MoontideMacro.exe: AutoHotkey v2 itself (signed by its authors), renamed
    # so it runs MoontideMacro.ahk next to it: players install nothing. Its
    # license ships beside it.
    $ahk = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
    $lic = Join-Path $env:ProgramFiles 'AutoHotkey\license.txt'
    if (-not (Test-Path $ahk)) { throw "AutoHotkey v2 not found at $ahk (needed for MoontideMacro.exe)" }
    if ($files -notcontains 'MoontideMacro.ahk') { throw 'MoontideMacro.ahk is not tracked; refusing to build' }
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $arc, $ahk, 'MoontideMacro.exe', [System.IO.Compression.CompressionLevel]::Optimal)
    if (-not (Test-Path $lic)) { throw "AutoHotkey's license.txt not found at $lic (it must ship with MoontideMacro.exe)" }
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $arc, $lic, 'AutoHotkey license.txt', [System.IO.Compression.CompressionLevel]::Optimal)
} finally {
    $arc.Dispose()
    Remove-Item -Recurse -Force $src -ErrorAction SilentlyContinue
}

Write-Host "Version : $version"
Write-Host "Files   : $($files.Count)"
Write-Host "Zip     : $zip"
Write-Host "Next    : create a GitHub release tagged v$version and attach this zip (nothing was published)."
