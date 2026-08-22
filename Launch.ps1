[CmdletBinding()]
param([string]$GamePath = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($GamePath)) { throw 'Pass -GamePath with your ANONYMOUS;CODE install directory.' }

$NormalInfoHash = '7485977DDB925E6159A5841571CA5BCA0A3495A4FAB0A1C16CF5A9AD6C9B47E4'
$FanInfoHash = 'ED9043D5902FF1F52EE4E9EECEE77ACB07EE376332B780D66D067B5F096B4248'
$PatchedBodyHash = '313C45210769AA50662FCEDB9C459975BFDF5BA334F3F9AA8CBDAC92F21118A2'
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
$gameExe = Join-Path $gameRoot 'game.exe'
$liveInfo = Join-Path $gameRoot 'windata\c0patch_info.psb.m'
$liveBody = Join-Path $gameRoot 'windata\c0patch_body.bin'
$stateRoot = Join-Path $gameRoot 'Anonymous-Code-Script-Extender'
$normalStateInfo = Join-Path $stateRoot 'c0patch_info.normal.psb.m'
$xdelta = Join-Path $PSScriptRoot 'xdelta3.exe'
$fanDelta = Join-Path $PSScriptRoot 'payload\fan-mode-info.vcdiff'
foreach ($path in @($gameExe, $liveInfo, $liveBody, $normalStateInfo, $xdelta, $fanDelta)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required game or patch file is missing: $path" }
}
if (@(Get-Process -Name 'game','MAGESgamelauncher' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close ANONYMOUS;CODE and its launcher before starting a session.'
}
if ((Get-Sha256 $liveBody) -ne $PatchedBodyHash -or (Get-Sha256 $normalStateInfo) -ne $NormalInfoHash) {
    throw 'The ANONYMOUS;CODE Patching Guide is not installed or its files were changed. Run Install.cmd first.'
}

$currentInfoHash = Get-Sha256 $liveInfo
if ($currentInfoHash -eq $FanInfoHash) {
    Copy-Item -LiteralPath $normalStateInfo -Destination $liveInfo -Force
    if ((Get-Sha256 $liveInfo) -ne $NormalInfoHash) { throw 'Could not recover normal mode from an interrupted session.' }
    Write-Host 'Recovered normal mode from an interrupted fan session.' -ForegroundColor Yellow
} elseif ($currentInfoHash -ne $NormalInfoHash) {
    throw "The live CoZ archive index is unknown: $currentInfoHash"
}

$nonce = [Guid]::NewGuid().ToString('N')
$fanInfo = Join-Path $stateRoot "c0patch_info.$nonce.fan"
try {
    & $xdelta -f -d -s $normalStateInfo $fanDelta $fanInfo
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fanInfo -PathType Leaf)) {
        throw 'Could not create the temporary fan-mode index.'
    }
    if ((Get-Sha256 $fanInfo) -ne $FanInfoHash) { throw 'The temporary fan-mode index failed verification.' }
    Copy-Item -LiteralPath $fanInfo -Destination $liveInfo -Force
    if ((Get-Sha256 $liveInfo) -ne $FanInfoHash) { throw 'Could not enable fan mode.' }

    Write-Host ''
    Write-Host '[INFO] Scene Compiled' -ForegroundColor Cyan
    Write-Host '[INFO] Writing Extra Data' -ForegroundColor Cyan
    Write-Host 'Keep this window open. Backup will be restored on game close.' -ForegroundColor Red
    Write-Host ''
    $gameProcess = Start-Process -FilePath $gameExe -WorkingDirectory $gameRoot -PassThru
    $gameProcess.WaitForExit()
} finally {
    if (Test-Path -LiteralPath $liveInfo -PathType Leaf) {
        $afterHash = Get-Sha256 $liveInfo
        if ($afterHash -eq $FanInfoHash) {
            Copy-Item -LiteralPath $normalStateInfo -Destination $liveInfo -Force
            if ((Get-Sha256 $liveInfo) -ne $NormalInfoHash) { throw 'Fan mode ended, but normal-mode restoration failed.' }
            Write-Host 'Backup restored.' -ForegroundColor Green
        } elseif ($afterHash -ne $NormalInfoHash) {
            throw "The archive index changed during play and was not overwritten: $afterHash"
        }
    }
    if (Test-Path -LiteralPath $fanInfo -PathType Leaf) { Remove-Item -LiteralPath $fanInfo -Force }
}
