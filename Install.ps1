[CmdletBinding()]
param([string]$GamePath = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($GamePath)) { throw 'Pass -GamePath with your ANONYMOUS;CODE install directory.' }

$PatchTitle = 'ANONYMOUS;CODE - Patching Guide v1.0.0'
$BaseInfoHash = '4F912510695F05465DC3E1E5A6BE5A22A8936E45AE403836FACB125BFCDE7502'
$BaseBodyHash = '71D9E8B978CE4AF6A7E20C00336656A9667BD6777F2D3FF2670C2FCDD6EA06E2'
$NormalInfoHash = '7485977DDB925E6159A5841571CA5BCA0A3495A4FAB0A1C16CF5A9AD6C9B47E4'
$FanInfoHash = 'ED9043D5902FF1F52EE4E9EECEE77ACB07EE376332B780D66D067B5F096B4248'
$PatchedBodyHash = '313C45210769AA50662FCEDB9C459975BFDF5BA334F3F9AA8CBDAC92F21118A2'
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-OrdinaryDirectory([string]$Path, [string]$Description) {
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { throw "$Description is not a directory: $Path" }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a symbolic link or junction: $Path"
    }
}

$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
$rootPath = [IO.Path]::GetPathRoot($gameRoot)
if ($gameRoot.TrimEnd('\') -eq $rootPath.TrimEnd('\')) { throw 'Refusing to use a drive root as the game directory.' }
Assert-OrdinaryDirectory $gameRoot 'Game path'
$gameExe = Join-Path $gameRoot 'game.exe'
$windata = Join-Path $gameRoot 'windata'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw "ANONYMOUS;CODE game.exe was not found in $gameRoot" }
if (-not (Test-Path -LiteralPath $windata -PathType Container)) { throw "ANONYMOUS;CODE windata was not found in $gameRoot" }
Assert-OrdinaryDirectory $windata 'windata'
if (@(Get-Process -Name 'game','MAGESgamelauncher' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close ANONYMOUS;CODE and its launcher before installing.'
}

$liveInfo = Join-Path $windata 'c0patch_info.psb.m'
$liveBody = Join-Path $windata 'c0patch_body.bin'
foreach ($path in @($liveInfo, $liveBody)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required CoZ archive is missing: $path" }
}
$stateRoot = Join-Path $gameRoot 'Anonymous-Code-Script-Extender'
$backupInfo = Join-Path $stateRoot 'c0patch_info.coz-backup.psb.m'
$backupBody = Join-Path $stateRoot 'c0patch_body.coz-backup.bin'
$normalStateInfo = Join-Path $stateRoot 'c0patch_info.normal.psb.m'
$currentInfoHash = Get-Sha256 $liveInfo
$currentBodyHash = Get-Sha256 $liveBody

if ($currentBodyHash -eq $PatchedBodyHash -and $currentInfoHash -in @($NormalInfoHash, $FanInfoHash)) {
    foreach ($path in @($backupInfo, $backupBody, $normalStateInfo)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed fan-patch state is incomplete: $path" }
    }
    if ((Get-Sha256 $backupInfo) -ne $BaseInfoHash -or (Get-Sha256 $backupBody) -ne $BaseBodyHash -or
        (Get-Sha256 $normalStateInfo) -ne $NormalInfoHash) {
        throw 'Installed fan-patch state failed verification. Nothing was changed.'
    }
    if ($currentInfoHash -eq $FanInfoHash) {
        Copy-Item -LiteralPath $normalStateInfo -Destination $liveInfo -Force
        if ((Get-Sha256 $liveInfo) -ne $NormalInfoHash) { throw 'Could not recover normal mode.' }
        Write-Host 'Recovered normal mode from an interrupted fan session.' -ForegroundColor Yellow
    }
    Write-Host "$PatchTitle is already installed and verified." -ForegroundColor Green
    exit 0
}

if ($currentInfoHash -ne $BaseInfoHash -or $currentBodyHash -ne $BaseBodyHash) {
    throw @"
Unsupported c0patch base. This release only installs over the exact CoZ build it was created from.
Current info: $currentInfoHash
Current body: $currentBodyHash
Expected info: $BaseInfoHash
Expected body: $BaseBodyHash
Uninstall the older ANONYMOUS;CODE fan-patch release first. Do not force installation.
"@
}

if (-not (Test-Path -LiteralPath $stateRoot)) { New-Item -ItemType Directory -Path $stateRoot | Out-Null }
Assert-OrdinaryDirectory $stateRoot 'Fan-patch state directory'
if (Test-Path -LiteralPath $backupInfo -PathType Leaf) {
    if ((Get-Sha256 $backupInfo) -ne $BaseInfoHash) { throw "Existing CoZ info backup is invalid: $backupInfo" }
} else { Copy-Item -LiteralPath $liveInfo -Destination $backupInfo }
if (Test-Path -LiteralPath $backupBody -PathType Leaf) {
    if ((Get-Sha256 $backupBody) -ne $BaseBodyHash) { throw "Existing CoZ body backup is invalid: $backupBody" }
} else { Copy-Item -LiteralPath $liveBody -Destination $backupBody }

$xdelta = Join-Path $PSScriptRoot 'xdelta3.exe'
$infoDelta = Join-Path $PSScriptRoot 'payload\c0patch_info.psb.m.vcdiff'
$bodyDelta = Join-Path $PSScriptRoot 'payload\c0patch_body.bin.vcdiff'
foreach ($path in @($xdelta, $infoDelta, $bodyDelta)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Patch payload is incomplete: $path" }
}
$nonce = [Guid]::NewGuid().ToString('N')
$newInfo = Join-Path $stateRoot "c0patch_info.$nonce.new"
$newBody = Join-Path $stateRoot "c0patch_body.$nonce.new"
try {
    & $xdelta -f -d -s $liveInfo $infoDelta $newInfo
    if ($LASTEXITCODE -ne 0) { throw 'xdelta failed while creating the normal fan archive index.' }
    & $xdelta -f -d -s $liveBody $bodyDelta $newBody
    if ($LASTEXITCODE -ne 0) { throw 'xdelta failed while creating the fan archive body.' }
    if ((Get-Sha256 $newInfo) -ne $NormalInfoHash -or (Get-Sha256 $newBody) -ne $PatchedBodyHash) {
        throw 'Generated fan archives failed verification.'
    }
    Copy-Item -LiteralPath $newInfo -Destination $normalStateInfo -Force
    try {
        Copy-Item -LiteralPath $newBody -Destination $liveBody -Force
        Copy-Item -LiteralPath $newInfo -Destination $liveInfo -Force
    } catch {
        Copy-Item -LiteralPath $backupBody -Destination $liveBody -Force
        Copy-Item -LiteralPath $backupInfo -Destination $liveInfo -Force
        throw
    }
    if ((Get-Sha256 $liveInfo) -ne $NormalInfoHash -or (Get-Sha256 $liveBody) -ne $PatchedBodyHash) {
        Copy-Item -LiteralPath $backupBody -Destination $liveBody -Force
        Copy-Item -LiteralPath $backupInfo -Destination $liveInfo -Force
        throw 'Installed files failed verification; the CoZ archive was restored.'
    }
    [ordered]@{
        patch = $PatchTitle; version = '1.0.0'; installedUtc = [DateTime]::UtcNow.ToString('o')
        baseInfoSha256 = $BaseInfoHash; baseBodySha256 = $BaseBodyHash
        normalInfoSha256 = $NormalInfoHash; fanInfoSha256 = $FanInfoHash; patchedBodySha256 = $PatchedBodyHash
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateRoot 'install-state.json') -Encoding utf8
} finally {
    foreach ($temporaryPath in @($newInfo, $newBody)) {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

Write-Host "$PatchTitle installed and verified." -ForegroundColor Green
Write-Host 'Run Launch.cmd with your game directory, then choose GAME START at the title screen.'
