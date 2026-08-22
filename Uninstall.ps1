[CmdletBinding()]
param([string]$GamePath = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($GamePath)) { throw 'Pass -GamePath with your ANONYMOUS;CODE install directory.' }

$BaseInfoHash = '4F912510695F05465DC3E1E5A6BE5A22A8936E45AE403836FACB125BFCDE7502'
$BaseBodyHash = '71D9E8B978CE4AF6A7E20C00336656A9667BD6777F2D3FF2670C2FCDD6EA06E2'
$NormalInfoHash = '7485977DDB925E6159A5841571CA5BCA0A3495A4FAB0A1C16CF5A9AD6C9B47E4'
$FanInfoHash = 'ED9043D5902FF1F52EE4E9EECEE77ACB07EE376332B780D66D067B5F096B4248'
$PatchedBodyHash = '313C45210769AA50662FCEDB9C459975BFDF5BA334F3F9AA8CBDAC92F21118A2'
# Preserve verified backups from the 0.6.5 patch during migration.
$LegacyNormalInfoHash = '0C1DFFD8E74CE31BF8737376CA1AF6994A83A5D51E2B38656F4BDA85F845C248'
$LegacyFanInfoHash = 'A158B5B349D79E693C2B3EB54D351B95BC31AD365785879C145B8182CF37096E'
$LegacyPatchedBodyHash = '5EAE803B71E3E181C3466995EFA90DDB0AEC29E9CF1FC7B8CE9373A8A5B32373'
$PreviousNormalInfoHash = 'CD525088431CB63BC65980AE24C23791092DC2D30A186099D35E3549E1170204'
$PreviousFanInfoHash = '65EA4CBCF4D4E5C898F3D5BA04B4209C2F2350E7461AC9B3995080BAE59BED66'
$PreviousPatchedBodyHash = '15142B83BF233DE300EC64D21276364C134E20C2BC7F5638FF8EB08A10D0C270'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
$gameExe = Join-Path $gameRoot 'game.exe'
$windata = Join-Path $gameRoot 'windata'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf) -or -not (Test-Path -LiteralPath $windata -PathType Container)) {
    throw "ANONYMOUS;CODE was not found at $gameRoot"
}
if (((Get-Item -LiteralPath $gameRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    ((Get-Item -LiteralPath $windata -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The game directory and windata must not be symbolic links or junctions.'
}
if (@(Get-Process -Name 'game','MAGESgamelauncher' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close ANONYMOUS;CODE and its launcher before uninstalling.'
}

$liveInfo = Join-Path $windata 'c0patch_info.psb.m'
$liveBody = Join-Path $windata 'c0patch_body.bin'
$stateRoot = Join-Path $gameRoot 'Anonymous-Code-Script-Extender'
$backupInfo = Join-Path $stateRoot 'c0patch_info.coz-backup.psb.m'
$backupBody = Join-Path $stateRoot 'c0patch_body.coz-backup.bin'
foreach ($path in @($liveInfo, $liveBody, $backupInfo, $backupBody)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required live file or CoZ backup is missing: $path" }
}
if (((Get-Item -LiteralPath $stateRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The fan-patch state directory must not be a symbolic link or junction.'
}
if ((Get-Sha256 $backupInfo) -ne $BaseInfoHash -or (Get-Sha256 $backupBody) -ne $BaseBodyHash) {
    throw 'The preserved CoZ backup failed verification. Nothing was changed.'
}
$currentInfoHash = Get-Sha256 $liveInfo
$currentBodyHash = Get-Sha256 $liveBody
if ($currentInfoHash -eq $BaseInfoHash -and $currentBodyHash -eq $BaseBodyHash) {
    Write-Host 'The fan patch is already uninstalled; the CoZ archive is active.' -ForegroundColor Green
    exit 0
}
if ($currentInfoHash -notin @($NormalInfoHash, $FanInfoHash, $LegacyNormalInfoHash, $LegacyFanInfoHash, $PreviousNormalInfoHash, $PreviousFanInfoHash) -or
    $currentBodyHash -notin @($PatchedBodyHash, $LegacyPatchedBodyHash, $PreviousPatchedBodyHash)) {
    throw @"
The live archive was modified after fan-patch installation.
Current info: $currentInfoHash
Current body: $currentBodyHash
Nothing was overwritten. Restore or update the other modification first.
"@
}
Copy-Item -LiteralPath $backupBody -Destination $liveBody -Force
Copy-Item -LiteralPath $backupInfo -Destination $liveInfo -Force
if ((Get-Sha256 $liveInfo) -ne $BaseInfoHash -or (Get-Sha256 $liveBody) -ne $BaseBodyHash) {
    throw 'CoZ restoration failed verification.'
}
Write-Host 'Fan patch uninstalled. The byte-identical CoZ archive has been restored.' -ForegroundColor Green
Write-Host "Backups remain in $stateRoot so the patch can be reinstalled safely."
