[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioJson,
    [string]$Label = '',
    [string]$SearchText = '',
    [string]$Speaker = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scenarioPath = (Resolve-Path -LiteralPath $ScenarioJson).Path
$scenario = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json

function Get-TextBody([object]$NativeText) {
    if ($null -eq $NativeText -or $NativeText.Count -lt 2 -or $null -eq $NativeText[1]) { return '' }
    return [string]$NativeText[1][0][1]
}

function Get-NormalizedTarget([object]$Edge) {
    if ($null -ne $Edge.PSObject.Properties['target'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Edge.target)) {
        return [string]$Edge.target
    }
    return '*start'
}

$selectedScenes = @($scenario.scenes)
if (-not [string]::IsNullOrWhiteSpace($Label)) {
    $selectedScenes = @($selectedScenes | Where-Object { [string]$_.label -ceq $Label })
    if ($selectedScenes.Count -ne 1) {
        throw "Expected one exact label '$Label'; found $($selectedScenes.Count)."
    }
}

if ([string]::IsNullOrWhiteSpace($Label) -and [string]::IsNullOrWhiteSpace($SearchText) -and
    [string]::IsNullOrWhiteSpace($Speaker)) {
    $selectedScenes | ForEach-Object {
        $edges = if ($null -ne $_.PSObject.Properties['nexts'] -and $null -ne $_.nexts) {
            @($_.nexts | ForEach-Object { "$([string]$_.storage) $(Get-NormalizedTarget $_)" }) -join '; '
        } else {
            '<none>'
        }
        [pscustomobject]@{
            Label = [string]$_.label
            DialoguePages = if ($null -ne $_.PSObject.Properties['texts'] -and $null -ne $_.texts) { $_.texts.Count } else { 0 }
            FirstLine = [long]$_.firstLine
            Checkpoints = [long]$_.spCount
            Next = $edges
        }
    } | Format-Table -AutoSize -Wrap
    exit 0
}

$matches = [Collections.Generic.List[object]]::new()
foreach ($scene in $selectedScenes) {
    if ($null -eq $scene.PSObject.Properties['texts'] -or $null -eq $scene.texts) { continue }
    for ($index = 0; $index -lt $scene.texts.Count; $index++) {
        $nativeText = $scene.texts[$index]
        if ($null -eq $nativeText) { continue }
        $nativeSpeaker = [string]$nativeText[0]
        $body = Get-TextBody $nativeText
        if (-not [string]::IsNullOrWhiteSpace($SearchText) -and $body.IndexOf($SearchText, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Speaker) -and $nativeSpeaker -cne $Speaker) { continue }
        $matches.Add([pscustomobject]@{
            Label = [string]$scene.label
            Page = $index + 1
            Speaker = $nativeSpeaker
            Text = $body
        })
    }
}

if ($matches.Count -eq 0) {
    Write-Warning 'No dialogue matched the supplied filters.'
    exit 0
}
$matches | Format-Table -AutoSize -Wrap

if (-not [string]::IsNullOrWhiteSpace($Label)) {
    $scene = $selectedScenes[0]
    Write-Host ''
    Write-Host 'Outgoing edges:'
    if ($null -ne $scene.PSObject.Properties['nexts'] -and $null -ne $scene.nexts) {
        $scene.nexts | ForEach-Object { Write-Host "  $([string]$_.storage) $(Get-NormalizedTarget $_)" }
    } else {
        Write-Host '  <none>'
    }
}
