[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $sourceRoot
Import-Module (Join-Path $sourceRoot 'Build\ScenarioBuild.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][object]$Expected,
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][string]$Case
    )

    if ($Expected -cne $Actual) {
        throw "$Case`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$MessagePattern,
        [Parameter(Mandatory = $true)][string]$Case
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notlike $MessagePattern) {
            throw "$Case`nUnexpected error: $($_.Exception.Message)"
        }
        return
    }
    throw "$Case`nExpected an exception matching: $MessagePattern"
}

Assert-Equal '5d41402abc4b2a76b9719d911017c592' (Get-Md5Hex 'hello') 'MD5 output is stable.'

$original = [pscustomobject]@{ nested = [pscustomobject]@{ value = 3 } }
$copy = Copy-JsonObject $original
$copy.nested.value = 7
Assert-Equal 3 $original.nested.value 'JSON copies do not share nested objects.'

$startEdge = New-SceneEdge ([pscustomobject]@{ storage = 'scene.ks'; target = '*start' })
Assert-Equal 'scene.ks' $startEdge.storage 'Scene edges preserve storage.'
Assert-Equal 0 $startEdge.type 'Scene edges use native type zero.'
Assert-Equal $false ($null -ne $startEdge.PSObject.Properties['target']) 'Default targets are omitted from native edges.'

$labelEdge = New-SceneEdge ([pscustomobject]@{ storage = 'scene.ks'; target = '*label' })
Assert-Equal '*label' $labelEdge.target 'Explicit targets are preserved.'
Assert-Equal '*start' (Get-NormalizedTarget ([pscustomobject]@{ storage = 'scene.ks' })) 'Missing targets normalize to start.'
Assert-Equal '*label' (Get-NormalizedTarget $labelEdge) 'Explicit targets survive normalization.'

Assert-Equal 1 (Get-PageMessageWindowType ([pscustomobject]@{ speaker = '' })) 'Narration uses the narration window.'
Assert-Equal 0 (Get-PageMessageWindowType ([pscustomobject]@{ speaker = 'ポロン' })) 'Spoken lines use the dialogue window.'
Assert-Equal 1 (Get-PageMessageWindowType ([pscustomobject]@{ speaker = 'ポロン'; window = 'narration' })) 'Explicit narration overrides the speaker default.'
Assert-Throws { Get-PageMessageWindowType ([pscustomobject]@{ speaker = ''; window = 'other' }) } '*Unknown page window style*' 'Unknown window styles fail validation.'

$edges = [object[]]@(
    [pscustomobject]@{ storage = 'first.ks'; type = 0 },
    [pscustomobject]@{ storage = 'second.ks'; target = '*label'; type = 0 }
)
Assert-Equal 0 (Get-UniqueSceneEdgeIndex $edges ([pscustomobject]@{ storage = 'first.ks'; target = '*start' }) 'Test') 'Default edge targets match explicit start targets.'
Assert-Equal 1 (Get-UniqueSceneEdgeIndex $edges ([pscustomobject]@{ storage = 'second.ks'; target = '*label' }) 'Test') 'A unique explicit edge is selected.'
Assert-Throws { Get-UniqueSceneEdgeIndex $edges ([pscustomobject]@{ storage = 'missing.ks'; target = '*start' }) 'Test' } '*found 0*' 'Missing edges fail closed.'

$texts = [object[]](ConvertFrom-Json -NoEnumerate '[["ポロン",[[0,"Hello"]]],["モモ",[[0,"Hello"]]],["ポロン",[[0,"hello"]]]]')
Assert-Equal 0 (Get-UniqueDialogueTextIndex $texts 'Hello' 'ポロン' 'Test') 'Dialogue matching includes the speaker when supplied.'
Assert-Equal 1 (Get-UniqueDialogueTextIndex $texts 'Hello' 'モモ' 'Test') 'Dialogue matching selects the requested speaker.'
Assert-Equal 2 (Get-UniqueDialogueTextIndex $texts 'hello' 'ポロン' 'Test') 'Dialogue matching is case-sensitive.'
Assert-Throws { Get-UniqueDialogueTextIndex $texts 'Hello' $null 'Test' } '*found 2*' 'Ambiguous dialogue fails closed.'

$lines = [object[]]@(0, [object[]]@('checkpoint'), 1, [object[]]@('display'), 2)
Assert-Equal 2 (Get-UniqueDisplayInstructionIndex $lines 1 'Test') 'The matching display instruction index is returned.'
Assert-Throws { Get-UniqueDisplayInstructionIndex ([object[]]@(1, 1)) 1 'Test' } '*not one matching display instruction*' 'Duplicate display instructions fail closed.'

$syntaxErrors = [Collections.Generic.List[string]]::new()
foreach ($path in Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $syntaxErrors.Add("$($path.FullName):$($errorRecord.Extent.StartLineNumber): $($errorRecord.Message)")
    }
}
if ($syntaxErrors.Count -gt 0) {
    throw "PowerShell syntax errors:`n$($syntaxErrors -join "`n")"
}

Write-Host 'PowerShell build tests passed.'
