[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioJsonRoot,
    [ValidateRange(1, 2147483647)]
    [int]$MinimumLines = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $ScenarioJsonRoot).Path
$counts = @{}
foreach ($file in Get-ChildItem -LiteralPath $root -File -Filter '*.ks.scn.m.json') {
    $scenario = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    foreach ($scene in $scenario.scenes) {
        if ($null -eq $scene.PSObject.Properties['texts'] -or $null -eq $scene.texts) { continue }
        foreach ($nativeText in $scene.texts) {
            if ($null -eq $nativeText) { continue }
            $speaker = [string]$nativeText[0]
            if ([string]::IsNullOrWhiteSpace($speaker)) { continue }
            if (-not $counts.ContainsKey($speaker)) { $counts[$speaker] = 0 }
            $counts[$speaker]++
        }
    }
}

$counts.GetEnumerator() |
    Where-Object { $_.Value -ge $MinimumLines } |
    Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Ascending = $true } |
    ForEach-Object { [pscustomobject]@{ Speaker = $_.Key; DialogueLines = $_.Value } } |
    Format-Table -AutoSize
