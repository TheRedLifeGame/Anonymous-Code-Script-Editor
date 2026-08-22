Set-StrictMode -Version Latest

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json)
}

function Get-Md5Hex {
    param([Parameter(Mandatory = $true)][string]$Value)

    $algorithm = [Security.Cryptography.MD5]::Create()
    try {
        $hashBytes = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function New-SceneEdge {
    param([Parameter(Mandatory = $true)][object]$Definition)

    $edge = [ordered]@{
        storage = [string]$Definition.storage
        type = 0
    }
    $target = [string]$Definition.target
    if (-not [string]::IsNullOrWhiteSpace($target) -and $target -ne '*start') {
        $edge['target'] = $target
    }
    return [pscustomobject]$edge
}

function Get-NormalizedTarget {
    param([Parameter(Mandatory = $true)][object]$Edge)

    if ($null -ne $Edge.PSObject.Properties['target'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Edge.target)) {
        return [string]$Edge.target
    }
    return '*start'
}

function Get-PageMessageWindowType {
    param([Parameter(Mandatory = $true)][object]$Page)

    if ($null -ne $Page.PSObject.Properties['window']) {
        switch ([string]$Page.window) {
            'narration' { return 1 }
            'dialogue' { return 0 }
            default { throw "Unknown page window style '$($Page.window)'." }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Page.speaker)) {
        return 1
    }
    return 0
}

function Get-UniqueSceneEdgeIndex {
    param(
        [Parameter(Mandatory = $true)][object[]]$Edges,
        [Parameter(Mandatory = $true)][object]$ExpectedNext,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $matches = [Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $Edges.Count; $index++) {
        if ([string]$Edges[$index].storage -eq [string]$ExpectedNext.storage -and
            (Get-NormalizedTarget $Edges[$index]) -eq (Get-NormalizedTarget $ExpectedNext)) {
            $matches.Add($index)
        }
    }
    if ($matches.Count -ne 1) {
        throw "$Context expected exactly one matching edge; found $($matches.Count)."
    }
    return $matches[0]
}

function Get-UniqueDialogueTextIndex {
    param(
        [Parameter(Mandatory = $true)][object[]]$Texts,
        [Parameter(Mandatory = $true)][string]$Text,
        [AllowNull()][object]$Speaker,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $matches = [Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $Texts.Count; $index++) {
        $nativeText = $Texts[$index]
        if ($null -eq $nativeText -or -not ($nativeText -is [Collections.IList]) -or $nativeText.Count -lt 2) {
            continue
        }
        $fragments = $nativeText[1]
        if ($null -eq $fragments -or -not ($fragments -is [Collections.IList]) -or $fragments.Count -lt 1) {
            continue
        }
        $firstFragment = $fragments[0]
        if ($null -eq $firstFragment -or -not ($firstFragment -is [Collections.IList]) -or $firstFragment.Count -lt 2) {
            continue
        }
        $nativeSpeaker = [string]$nativeText[0]
        $nativeBody = [string]$firstFragment[1]
        if ($nativeBody -ceq $Text -and ($null -eq $Speaker -or $nativeSpeaker -ceq [string]$Speaker)) {
            $matches.Add($index)
        }
    }
    if ($matches.Count -ne 1) {
        throw "$Context expected one exact dialogue match; found $($matches.Count)."
    }
    return $matches[0]
}

function Get-UniqueDisplayInstructionIndex {
    param(
        [Parameter(Mandatory = $true)][object[]]$Lines,
        [Parameter(Mandatory = $true)][long]$TextNumber,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $matches = [Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $instruction = $Lines[$index]
        if (($instruction -is [int] -or $instruction -is [long]) -and [long]$instruction -eq $TextNumber) {
            $matches.Add($index)
        }
    }
    if ($matches.Count -ne 1) {
        throw "$Context found the dialogue table entry but not one matching display instruction."
    }
    return $matches[0]
}

Export-ModuleMember -Function @(
    'Copy-JsonObject'
    'Get-Md5Hex'
    'New-SceneEdge'
    'Get-NormalizedTarget'
    'Get-PageMessageWindowType'
    'Get-UniqueSceneEdgeIndex'
    'Get-UniqueDialogueTextIndex'
    'Get-UniqueDisplayInstructionIndex'
)
