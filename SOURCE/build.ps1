[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExtractRoot,
    [Parameter(Mandatory = $true)]
    [string]$ToolRoot,
    [Parameter(Mandatory = $true)]
    [string]$BaseScenarioJsonRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,
    [string]$ProjectPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceRoot = $PSScriptRoot
Import-Module (Join-Path $sourceRoot 'Build\ScenarioBuild.psm1') -Force
$projectPathResolved = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Join-Path $sourceRoot 'project.json'
} else {
    (Resolve-Path -LiteralPath $ProjectPath).Path
}
$extractRootResolved = (Resolve-Path -LiteralPath $ExtractRoot).Path
$toolRootResolved = (Resolve-Path -LiteralPath $ToolRoot).Path
$baseScenarioRootResolved = (Resolve-Path -LiteralPath $BaseScenarioJsonRoot).Path
$outputParent = Split-Path -Parent $OutputRoot
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}
$outputRootResolved = [IO.Path]::GetFullPath($OutputRoot)

$sourceArchiveDir = Join-Path $extractRootResolved 'c0patch'
$sourceBody = Join-Path $extractRootResolved 'c0patch_body.bin'
$sourceManifest = Join-Path $extractRootResolved 'c0patch_info.psb.m.json'
$sourceManifestResources = Join-Path $extractRootResolved 'c0patch_info.psb.m.resx.json'
$sceneListSourceJson = Join-Path $sourceArchiveDir 'scenario\scenelist.scn.m.json'
$sceneListSourceResources = Join-Path $sourceArchiveDir 'scenario\scenelist.scn.m.resx.json'
$psBuild = Join-Path $toolRootResolved 'FreeMote\PsBuild.exe'
$psbDecompile = Join-Path $toolRootResolved 'FreeMote\PsbDecompile.exe'

foreach ($required in @($sourceArchiveDir, $sourceBody, $sourceManifest, $sourceManifestResources,
    $baseScenarioRootResolved, $sceneListSourceJson, $sceneListSourceResources,
    $psBuild, $psbDecompile)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required build input is missing: $required"
    }
}

if (Test-Path -LiteralPath $outputRootResolved) {
    $resolvedExisting = (Resolve-Path -LiteralPath $outputRootResolved).Path
    $allowedParent = [IO.Path]::GetFullPath((Join-Path $sourceRoot '..'))
    if (-not $resolvedExisting.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace output outside the fan-patch work directory: $resolvedExisting"
    }
    if (((Get-Item -LiteralPath $resolvedExisting -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace a linked output directory: $resolvedExisting"
    }
    Remove-Item -LiteralPath $resolvedExisting -Recurse -Force
}

function Set-DialogueLineNames([object]$Node, [string[]]$Names, [ref]$DisplayIndex) {
    if ($null -eq $Node -or $Node -is [string] -or -not ($Node -is [System.Collections.IList])) {
        return
    }
    if ($Node.Count -gt 0 -and $Node[0] -eq 'startline') {
        $array = [object[]]$Node
        $textPosition = [Array]::IndexOf($array, 'text')
        $noTextPosition = [Array]::IndexOf($array, 'notext')
        if ($textPosition -ge 0 -and $Node[$textPosition + 1] -eq 1 -and $noTextPosition -lt 0) {
            $namePosition = [Array]::IndexOf($array, 'name')
            if ($namePosition -lt 0) {
                throw 'A display startline command is missing its name field.'
            }
            if ($DisplayIndex.Value -ge $Names.Count) {
                throw 'The native template contains more dialogue commands than story pages.'
            }
            $Node[$namePosition + 1] = $Names[$DisplayIndex.Value]
            $DisplayIndex.Value++
        }
    }
    foreach ($child in $Node) {
        Set-DialogueLineNames $child $Names $DisplayIndex
    }
}

function Set-Presentation([object]$Scene, [object]$Presentation) {
    if ($null -eq $Presentation) { return }
    $background = if ($Presentation.PSObject.Properties.Name -contains 'background') { [string]$Presentation.background } else { '' }
    $music = if ($Presentation.PSObject.Properties.Name -contains 'music') { [string]$Presentation.music } else { '' }
    $hideUnlisted = if ($Presentation.PSObject.Properties.Name -contains 'hideUnlisted') { [bool]$Presentation.hideUnlisted } else { $false }
    $characters = @{}
    if ($Presentation.PSObject.Properties.Name -contains 'characters') {
        foreach ($spec in @($Presentation.characters)) {
            if ($null -eq $spec -or -not ($spec.PSObject.Properties.Name -contains 'id')) { continue }
            $id = [string]$spec.id
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $characters[$id] = $spec
        }
    }
    $state = @{ firstDataSeen = $false; firstData = $null; firstNode = $null }

    function Update-PresentationNode([object]$Node) {
        if ($null -eq $Node -or $Node -is [string]) { return }
        if ($Node -is [System.Collections.IList]) {
            foreach ($child in $Node) { Update-PresentationNode $child }
            return
        }
        $nodeProperties = @($Node.PSObject.Properties)
        if ((@($nodeProperties | Where-Object { $_.Name -eq 'data' })).Count -gt 0 -and $null -ne $Node.data) {
            $data = [Collections.Generic.List[object]]::new()
            foreach ($entry in @($Node.data)) { [void]$data.Add($entry) }
            if (-not $state.firstDataSeen) {
                $state.firstDataSeen = $true
                $state.firstData = $data
                $state.firstNode = $Node
            }
            foreach ($entry in $data) {
                $entryArray = @($entry)
                if ($entryArray.Count -lt 3 -or $null -eq $entryArray[2]) { continue }
                $name = [string]$entryArray[0]
                $class = [string]$entryArray[1]
                $definition = $entryArray[2]
                if ($class -eq 'stage' -and $name -eq 'bg' -and $background) {
                    if (-not ($definition.PSObject.Properties.Name -contains 'redraw') -or $null -eq $definition.redraw) {
                        $definition | Add-Member -NotePropertyName redraw -NotePropertyValue ([pscustomobject]@{})
                    }
                    if (-not ($definition.redraw.PSObject.Properties.Name -contains 'imageFile') -or $null -eq $definition.redraw.imageFile) {
                        $definition.redraw | Add-Member -NotePropertyName imageFile -NotePropertyValue ([pscustomobject]@{})
                    }
                    $definition.redraw.imageFile.file = $background
                }
                if ($class -eq 'bgm' -and $name -eq 'bgm' -and $music -and
                    $null -ne $definition.PSObject.Properties['replay'] -and
                    $null -ne $definition.replay) {
                    $definition.replay.filename = $music
                }
                if ($class -eq 'character') {
                    $configured = $characters.ContainsKey($name)
                    if ($configured) {
                        $spec = $characters[$name]
                        $show = -not ($spec.PSObject.Properties.Name -contains 'show') -or [bool]$spec.show
                        $definition.showmode = if ($show) { 3 } else { 0 }
                        if (-not ($definition.PSObject.Properties.Name -contains 'redraw') -or $null -eq $definition.redraw) {
                            $definition | Add-Member -NotePropertyName redraw -NotePropertyValue ([pscustomobject]@{})
                        }
                        $dispValue = if ($show) { 2 } else { 0 }
                        $redrawProperties = @($definition.redraw.PSObject.Properties)
                        if ((@($redrawProperties | Where-Object { $_.Name -eq 'disp' })).Count -gt 0) { $definition.redraw.disp = $dispValue } else { $definition.redraw | Add-Member -NotePropertyName disp -NotePropertyValue $dispValue }
                        if ((@($redrawProperties | Where-Object { $_.Name -eq 'imageFile' })).Count -eq 0) {
                            $definition.redraw | Add-Member -NotePropertyName imageFile -NotePropertyValue ([pscustomobject]@{})
                        } elseif ($null -eq $definition.redraw.imageFile -or $definition.redraw.imageFile -is [string]) {
                            $definition.redraw.imageFile = [pscustomobject]@{}
                        }
                        if ($spec.PSObject.Properties.Name -contains 'file' -and $spec.file) {
                            $imageProperties = @($definition.redraw.imageFile.PSObject.Properties)
                            if ((@($imageProperties | Where-Object { $_.Name -eq 'file' })).Count -gt 0) { $definition.redraw.imageFile.file = [string]$spec.file } else { $definition.redraw.imageFile | Add-Member -NotePropertyName file -NotePropertyValue ([string]$spec.file) }
                        }
                        if ($spec.PSObject.Properties.Name -contains 'position' -and $spec.position) {
                            $redrawProperties = @($definition.redraw.PSObject.Properties)
                            if ((@($redrawProperties | Where-Object { $_.Name -eq 'posName' })).Count -gt 0) { $definition.redraw.posName = [string]$spec.position } else { $definition.redraw | Add-Member -NotePropertyName posName -NotePropertyValue ([string]$spec.position) }
                        }
                    } elseif ($hideUnlisted) {
                        $definition.showmode = 0
                        if ($definition.PSObject.Properties.Name -contains 'redraw' -and $null -ne $definition.redraw) { $definition.redraw.disp = 0 }
                    }
                }
            }
            $Node.data = [object[]]$data.ToArray()
        }
        foreach ($property in $nodeProperties) {
            if ($property.Name -eq 'data' -or $null -eq $property.Value) { continue }
            Update-PresentationNode $property.Value
        }
    }

    Update-PresentationNode $Scene.lines
    if ($state.firstDataSeen) {
        foreach ($id in $characters.Keys) {
            $already = @($state.firstData | Where-Object { @($_).Count -ge 1 -and [string]@($_)[0] -eq $id -and @($_).Count -ge 2 -and [string]@($_)[1] -eq 'character' })
            if ($already.Count -gt 0) { continue }
            $spec = $characters[$id]
            $show = -not ($spec.PSObject.Properties.Name -contains 'show') -or [bool]$spec.show
            $file = if ($spec.PSObject.Properties.Name -contains 'file') { [string]$spec.file } else { '' }
            if ([string]::IsNullOrWhiteSpace($file)) { throw "Presentation character '$id' is missing a file." }
            $position = if ($spec.PSObject.Properties.Name -contains 'position' -and $spec.position) { [string]$spec.position } else { '中' }
            $image = [pscustomobject]@{ file = $file; options = $null }
            $redraw = [pscustomobject]@{ disp = if ($show) { 2 } else { 0 }; imageFile = $image; posName = $position }
            $definition = [pscustomobject]@{ action = @(); class = 'character'; link = ''; name = $id; redraw = $redraw; showmode = if ($show) { 3 } else { 0 }; type = $null }
            [void]$state.firstData.Add([object[]]@($id, 'character', $definition))
        }
        if ($null -ne $state.firstNode) {
            $state.firstNode.data = [object[]]$state.firstData.ToArray()
        }
    }
}

function Set-SpeakerFocusTimeline([object]$Scene, [object]$Presentation, [object[]]$Pages) {
    if ($null -eq $Presentation -or
        -not ($Presentation.PSObject.Properties.Name -contains 'speakerFocus') -or
        -not [bool]$Presentation.speakerFocus) {
        return
    }

    $characterIds = [Collections.Generic.List[string]]::new()
    $characterSpecs = @{}
    foreach ($spec in @($Presentation.characters)) {
        if ($null -eq $spec -or -not ($spec.PSObject.Properties.Name -contains 'id')) { continue }
        $id = [string]$spec.id
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $characterIds.Add($id)
            $characterSpecs[$id] = $spec
        }
    }
    if ($characterIds.Count -eq 0) {
        throw 'speakerFocus presentation mode requires at least one configured character.'
    }

    $speakerGroups = @{}
    if ($Presentation.PSObject.Properties.Name -contains 'speakerGroups' -and
        $null -ne $Presentation.speakerGroups) {
        foreach ($groupProperty in $Presentation.speakerGroups.PSObject.Properties) {
            $groupIds = [Collections.Generic.List[string]]::new()
            foreach ($groupIdValue in @($groupProperty.Value)) {
                $groupId = [string]$groupIdValue
                if (-not $characterIds.Contains($groupId)) {
                    throw "speakerFocus group '$($groupProperty.Name)' references unconfigured character '$groupId'."
                }
                $groupIds.Add($groupId)
            }
            $speakerGroups[[string]$groupProperty.Name] = [string[]]$groupIds.ToArray()
        }
    }

    $initialCheckpoint = $null
    $finalCheckpoint = $null
    $characterDefinitions = @{}
    foreach ($instruction in @($Scene.lines)) {
        if (-not ($instruction -is [System.Collections.IList]) -or $instruction.Count -lt 2 -or
            $null -eq $instruction[1] -or $instruction[1] -is [string] -or
            $null -eq $instruction[1].PSObject.Properties['data']) {
            continue
        }
        if ($null -eq $initialCheckpoint) { $initialCheckpoint = Copy-JsonObject $instruction }
        $finalCheckpoint = Copy-JsonObject $instruction
        foreach ($entry in @($instruction[1].data)) {
            $entryArray = @($entry)
            if ($entryArray.Count -ge 3 -and [string]$entryArray[1] -eq 'character' -and
                $characterIds.Contains([string]$entryArray[0])) {
                $characterDefinition = Copy-JsonObject $entryArray[2]
                if ($characterDefinition.PSObject.Properties.Name -contains 'action') {
                    $characterDefinition.action = @()
                }
                if ($characterDefinition.PSObject.Properties.Name -contains 'redraw' -and
                    $null -ne $characterDefinition.redraw) {
                    if ($characterDefinition.redraw.PSObject.Properties.Name -contains 'redraw') {
                        $characterDefinition.redraw.redraw = $null
                    }
                    if ($characterDefinition.redraw.PSObject.Properties.Name -contains 'imageFile' -and
                        $null -ne $characterDefinition.redraw.imageFile -and
                        $characterDefinition.redraw.imageFile.PSObject.Properties.Name -contains 'options') {
                        $characterDefinition.redraw.imageFile.options = $null
                    }
                }
                $spec = $characterSpecs[[string]$entryArray[0]]
                $x = if ($spec.PSObject.Properties.Name -contains 'x') { [double]$spec.x } else { 0.0 }
                $y = if ($spec.PSObject.Properties.Name -contains 'y') { [double]$spec.y } else { 0.0 }
                $z = if ($spec.PSObject.Properties.Name -contains 'z') { [double]$spec.z } else { 0.0 }
                $order = if ($spec.PSObject.Properties.Name -contains 'order') { [int]$spec.order } else { 0 }
                $layoutActions = [Collections.Generic.List[object]]::new()
                [void]$layoutActions.Add([object[]]@('xpos', $x))
                [void]$layoutActions.Add([object[]]@('ypos', $y))
                [void]$layoutActions.Add([object[]]@('zpos', $z))
                [void]$layoutActions.Add([object[]]@('order', $order))
                if ($spec.PSObject.Properties.Name -contains 'scale') {
                    [void]$layoutActions.Add([object[]]@('zoomx', [double]$spec.scale))
                    [void]$layoutActions.Add([object[]]@('zoomy', [double]$spec.scale))
                }
                if ($characterDefinition.PSObject.Properties.Name -contains 'action') {
                    $characterDefinition.action = [object[]]$layoutActions.ToArray()
                } else {
                    $characterDefinition | Add-Member -NotePropertyName action -NotePropertyValue ([object[]]$layoutActions.ToArray())
                }
                $characterDefinitions[[string]$entryArray[0]] = $characterDefinition
            }
        }
    }
    if ($null -eq $initialCheckpoint -or $null -eq $finalCheckpoint) {
        throw 'speakerFocus presentation mode could not find a native environment checkpoint.'
    }
    foreach ($id in $characterIds) {
        if (-not $characterDefinitions.ContainsKey($id)) {
            throw "speakerFocus presentation mode could not construct character '$id'."
        }
    }

    $allowedEnvironmentNames = @('bg', 'bgm', 'retina_frame')
    $baseState = Copy-JsonObject $initialCheckpoint[1]
    $baseData = [Collections.Generic.List[object]]::new()
    foreach ($entry in @($baseState.data)) {
        $entryArray = @($entry)
        if ($entryArray.Count -lt 3 -or [string]$entryArray[0] -notin $allowedEnvironmentNames) { continue }
        $definition = $entryArray[2]
        if ([string]$entryArray[0] -eq 'bgm' -and $null -ne $definition.replay -and
            $Presentation.PSObject.Properties.Name -contains 'music' -and
            -not [string]::IsNullOrWhiteSpace([string]$Presentation.music)) {
            $definition.replay.filename = [string]$Presentation.music
        }
        if ([string]$entryArray[0] -eq 'bg') {
            $definition.showmode = 3
            if ($definition.PSObject.Properties.Name -contains 'action') {
# PowerShell unwraps one-item arrays; the engine still requires action[][].
                $backgroundActions = New-Object object[] 2
                $backgroundActions[0] = [object[]]@('zpos', 233.33333333333337)
                $backgroundActions[1] = [object[]]@('zpos', 233.33333333333337)
                $definition.action = $backgroundActions
            }
        }
        [void]$baseData.Add([object[]]@($entryArray[0], $entryArray[1], $definition))
    }
    foreach ($id in $characterIds) {
        $definition = Copy-JsonObject $characterDefinitions[$id]
        $definition.showmode = 0
        if ($definition.PSObject.Properties.Name -contains 'redraw' -and $null -ne $definition.redraw) {
            $definition.redraw.disp = 0
        }
        [void]$baseData.Add([object[]]@($id, 'character', $definition))
    }
    $baseState.data = [object[]]$baseData.ToArray()
    $baseState.env = [pscustomobject]@{ name = 'env' }
    $baseState.msgwin = 0

    $textCheckpoints = @{}
    for ($lineIndex = 0; $lineIndex -lt $Scene.lines.Count - 1; $lineIndex++) {
        $instruction = $Scene.lines[$lineIndex]
        if (-not ($instruction -is [int] -or $instruction -is [long])) { continue }
        $textNumber = [int]$instruction
        if ($textNumber -lt 1 -or $textNumber -gt $Pages.Count) { continue }
        $candidate = $Scene.lines[$lineIndex + 1]
        if ($candidate -is [System.Collections.IList] -and $candidate.Count -ge 2 -and
            ($candidate[0] -is [int] -or $candidate[0] -is [long])) {
            $textCheckpoints[$textNumber] = Copy-JsonObject $candidate
        }
    }
    for ($textNumber = 1; $textNumber -le $Pages.Count; $textNumber++) {
        if (-not $textCheckpoints.ContainsKey($textNumber)) {
            throw "speakerFocus presentation mode could not find the checkpoint for dialogue page $textNumber."
        }
    }

    $newLines = [Collections.Generic.List[object]]::new()
    $initialCheckpoint[1] = Copy-JsonObject $baseState
    [void]$newLines.Add($initialCheckpoint)
    $messageWindowType = 0
    for ($pageIndex = 0; $pageIndex -lt $Pages.Count; $pageIndex++) {
        $speaker = [string]$Pages[$pageIndex].speaker
        $desiredMessageWindowType = Get-PageMessageWindowType $Pages[$pageIndex]
        $groupKey = if ([string]::IsNullOrWhiteSpace($speaker)) { '$narration' } else { $speaker }
        $visibleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if ($speakerGroups.ContainsKey($groupKey)) {
            foreach ($groupId in $speakerGroups[$groupKey]) { [void]$visibleIds.Add($groupId) }
        } elseif ([string]::IsNullOrWhiteSpace($speaker)) {
            foreach ($id in $characterIds) {
                $spec = $characterSpecs[$id]
                if (-not ($spec.PSObject.Properties.Name -contains 'show') -or [bool]$spec.show) {
                    [void]$visibleIds.Add($id)
                }
            }
        } elseif ($characterIds.Contains($speaker)) {
            [void]$visibleIds.Add($speaker)
        }
        $updates = [Collections.Generic.List[object]]::new()
        if ($desiredMessageWindowType -ne $messageWindowType) {
            $typeText = [string]$desiredMessageWindowType
            [void]$updates.Add([object[]]@(
                'tag',
                [pscustomobject]@{
                    runLineStr = "[msgwin type=$typeText]"
                    taglist = [object[]]@('tagname', 'type')
                    tagname = 'msgwin'
                    type = $typeText
                }
            ))
            $messageWindowType = $desiredMessageWindowType
        }
        foreach ($id in $characterIds) {
            $show = $visibleIds.Contains($id)
            if ($show) {
                $definition = Copy-JsonObject $characterDefinitions[$id]
                $definition.showmode = 3
                if ($definition.PSObject.Properties.Name -contains 'redraw' -and $null -ne $definition.redraw) {
                    $definition.redraw.disp = 2
                }
                [void]$updates.Add($definition)
            } else {
                [void]$updates.Add([pscustomobject]@{ name = $id; showmode = 2 })
            }
        }
        [void]$newLines.Add([object[]]@(
            'envupdate', 'update', [object[]]$updates.ToArray(),
            'trans', [pscustomobject]@{ method = 'crossfade'; time = '200' }
        ))
# Generated dialogue pages use mode 1. Mode 0 is reserved for native control
# startlines; using it without the native window setup leaves a black screen.
        [void]$newLines.Add([object[]]@('startline', 'vflag', 0, 'name', $speaker, 'text', 1))
        $textNumber = $pageIndex + 1
        [void]$newLines.Add($textNumber)
        [void]$newLines.Add($textCheckpoints[$textNumber])
    }
    [void]$newLines.Add([object[]]@('er', 'all', 'true'))
    $finalCheckpoint[1] = Copy-JsonObject $baseState
    [void]$newLines.Add($finalCheckpoint)
    $Scene.lines = [object[]]$newLines.ToArray()
}

function New-BlankSceneTimeline([object]$Scene, [int]$PageCount) {
    if ($PageCount -lt 1) {
        throw 'Blank scenes require at least one dialogue page.'
    }

    $initialCheckpoint = $null
    $finalCheckpoint = $null
    $prototypeTextCheckpoint = $null
    $linkedTextCheckpoint = $null
    foreach ($instruction in @($Scene.lines)) {
        if (-not ($instruction -is [System.Collections.IList]) -or $instruction.Count -lt 2 -or
            $null -eq $instruction[1] -or $instruction[1] -is [string] -or
            $null -eq $instruction[1].PSObject.Properties['data']) {
            continue
        }
        if ($null -eq $initialCheckpoint) {
            $initialCheckpoint = Copy-JsonObject $instruction
        }
        $finalCheckpoint = Copy-JsonObject $instruction
    }

    for ($lineIndex = 0; $lineIndex -lt $Scene.lines.Count - 1; $lineIndex++) {
        $instruction = $Scene.lines[$lineIndex]
        if (-not ($instruction -is [int] -or $instruction -is [long])) { continue }
        $candidate = $Scene.lines[$lineIndex + 1]
        if ($candidate -is [System.Collections.IList] -and $candidate.Count -ge 2 -and
            ($candidate[0] -is [int] -or $candidate[0] -is [long])) {
            if ($null -eq $prototypeTextCheckpoint) {
                $prototypeTextCheckpoint = Copy-JsonObject $candidate
            }
            if ($candidate.Count -ge 6 -and $null -ne $candidate[5]) {
                $linkedTextCheckpoint = Copy-JsonObject $candidate
                break
            }
        }
    }
    if ($null -eq $initialCheckpoint -or $null -eq $finalCheckpoint -or $null -eq $prototypeTextCheckpoint) {
        throw 'Blank scene mode could not find a usable native message shell.'
    }

    $baseCheckpointId = if ($prototypeTextCheckpoint[0] -is [int] -or $prototypeTextCheckpoint[0] -is [long]) {
        [int]$prototypeTextCheckpoint[0]
    } else {
        2
    }
    $sourceLine = if ($prototypeTextCheckpoint.Count -ge 5 -and $null -ne $prototypeTextCheckpoint[4]) {
        [long]$prototypeTextCheckpoint[4]
    } elseif ($initialCheckpoint.Count -ge 5 -and $null -ne $initialCheckpoint[4]) {
        [long]$initialCheckpoint[4]
    } else {
        [long]$Scene.firstLine
    }
    $textMode = if ($null -ne $linkedTextCheckpoint -and $linkedTextCheckpoint.Count -ge 6 -and
        $null -ne $linkedTextCheckpoint[5]) {
        [long]$linkedTextCheckpoint[5]
    } elseif ($initialCheckpoint.Count -ge 6 -and $null -ne $initialCheckpoint[5]) {
        [long]$initialCheckpoint[5]
    } else {
        192L
    }
    $newLines = [Collections.Generic.List[object]]::new()
    [void]$newLines.Add($initialCheckpoint)
    for ($pageIndex = 0; $pageIndex -lt $PageCount; $pageIndex++) {
        [void]$newLines.Add([object[]]@('startline', 'vflag', 0, 'name', '', 'text', 1))
        $textNumber = $pageIndex + 1
        [void]$newLines.Add($textNumber)
# Checkpoints must link through fields 3 and 6 or the engine cannot reach the
# next page; a terminal-only checkpoint can compile but renders black.
        $checkpoint = if ($textNumber -lt $PageCount) {
            [object[]]@(
                [long]($baseCheckpointId + $pageIndex),
                [long]$textNumber,
                [long]($textNumber + 1),
                $null,
                $sourceLine,
                $textMode,
                $null,
                $null
            )
        } else {
            [object[]]@(
                [long]($baseCheckpointId + $pageIndex),
                [long]$textNumber,
                $null,
                $null,
                $sourceLine
            )
        }
        [void]$newLines.Add($checkpoint)
    }
    [void]$newLines.Add([object[]]@('er', 'all', 'true'))
# Keep the closing checkpoint outside the generated text ID range.
    $finalCheckpoint[0] = [long]($baseCheckpointId + $PageCount)
    [void]$newLines.Add($finalCheckpoint)
    $Scene.lines = [object[]]$newLines.ToArray()
}

function Compile-Scenario([object]$Scenario, [string]$JsonPath, [string]$CompiledPath, [string]$ResourceTemplate) {
    $resxPath = $JsonPath -replace '\.json$', '.resx.json'
    $Scenario | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $JsonPath -Encoding utf8
    Copy-Item -LiteralPath $ResourceTemplate -Destination $resxPath
    & $psBuild -nr -o $CompiledPath $JsonPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $CompiledPath -PathType Leaf)) {
        throw "Failed to compile scenario archive entry: $CompiledPath"
    }
}

function Pack-MiniArchive([string]$MiniRoot) {
    $scenarioRoot = Join-Path $MiniRoot 'c0patch\scenario'
    $entries = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $scenarioRoot -File -Filter '*.m' | Sort-Object Name) {
        $entries["scenario/$($file.Name)"] = @(0, 0)
    }
    $manifest = [ordered]@{
        expire_suffix_list = @('.psb.m')
        file_info = $entries
        info = 'archive'
        version = 1.0
    }
    $manifestPath = Join-Path $MiniRoot 'c0patch_info.psb.m.json'
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Copy-Item -LiteralPath $sourceManifestResources -Destination $MiniRoot
    Push-Location $MiniRoot
    try {
        & $psBuild info-psb 'c0patch_info.psb.m.json'
        if ($LASTEXITCODE -ne 0) { throw "Failed to pack mini archive: $MiniRoot" }
        & $psbDecompile info-psb -k 5fWhAHt4zVn2X 'c0patch_info.psb.m'
        if ($LASTEXITCODE -ne 0) { throw "Failed to read back mini archive offsets: $MiniRoot" }
    } finally {
        Pop-Location
    }
}

function Compile-Index([object]$Manifest, [string]$IndexRoot, [string]$Destination) {
    New-Item -ItemType Directory -Path $IndexRoot -Force | Out-Null
    $json = Join-Path $IndexRoot 'c0patch_info.psb.m.json'
    $resx = Join-Path $IndexRoot 'c0patch_info.psb.m.resx.json'
    $compiled = Join-Path $IndexRoot 'c0patch_info.psb.m'
    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $json -Encoding utf8
    Copy-Item -LiteralPath $sourceManifestResources -Destination $resx
    & $psBuild -nr -o $compiled $json
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $compiled -PathType Leaf)) {
        throw "Failed to compile archive index: $Destination"
    }
    Copy-Item -LiteralPath $compiled -Destination $Destination
}

New-Item -ItemType Directory -Path $outputRootResolved -Force | Out-Null
$normalMiniRoot = Join-Path $outputRootResolved 'mini-normal'
$fanMiniRoot = Join-Path $outputRootResolved 'mini-fan-mode'
$normalScenarioRoot = Join-Path $normalMiniRoot 'c0patch\scenario'
$fanScenarioRoot = Join-Path $fanMiniRoot 'c0patch\scenario'
New-Item -ItemType Directory -Path $normalScenarioRoot -Force | Out-Null
New-Item -ItemType Directory -Path $fanScenarioRoot -Force | Out-Null

$project = Get-Content -LiteralPath $projectPathResolved -Raw | ConvertFrom-Json
if ($project.schemaVersion -notin @(1, 2)) {
    throw "Unsupported scene-project schema version: $($project.schemaVersion)"
}
$templateSpecs = [ordered]@{}
foreach ($sceneDefinition in $project.scenes) {
    if ($null -ne $templateSpecs[$sceneDefinition.id]) {
        throw "Duplicate scene id: $($sceneDefinition.id)"
    }
    $templateSpecs[$sceneDefinition.id] = $sceneDefinition.template
}
$templateRoots = [ordered]@{}
foreach ($spec in $templateSpecs.Values) {
    $jsonPath = Join-Path $baseScenarioRootResolved "$($spec.storage).scn.m.json"
    $resxPath = Join-Path $baseScenarioRootResolved "$($spec.storage).scn.m.resx.json"
    foreach ($requiredTemplate in @($jsonPath, $resxPath)) {
        if (-not (Test-Path -LiteralPath $requiredTemplate -PathType Leaf)) {
            throw "Native scenario template is missing: $requiredTemplate"
        }
    }
    if ($null -eq $templateRoots[$spec.storage]) {
        $templateRoots[$spec.storage] = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    }
}

$voicedCharacters = @($project.voiceCharacters)
$voicePools = [ordered]@{}
$voiceById = [ordered]@{}
foreach ($character in $voicedCharacters) {
    $voicePools[$character] = [Collections.Generic.List[object]]::new()
    $voiceById[$character] = @{}
}
$voiceSourceFiles = @(Get-ChildItem -LiteralPath $baseScenarioRootResolved -Filter '*.ks.scn.m.json' -File -Recurse)
foreach ($voiceSourceFile in $voiceSourceFiles) {
    $root = Get-Content -LiteralPath $voiceSourceFile.FullName -Raw | ConvertFrom-Json
    foreach ($sourceScene in $root.scenes) {
        if ($null -eq $sourceScene.PSObject.Properties['texts']) {
            continue
        }
        foreach ($sourceText in @($sourceScene.texts | Where-Object { $null -ne $_ })) {
            $speaker = [string]$sourceText[0]
            if ($speaker -in $voicedCharacters -and $sourceText.Count -gt 2 -and $null -ne $sourceText[2]) {
                $voiceBlock = [object[]]@($sourceText[2] | ForEach-Object { Copy-JsonObject $_ })
                if ($voiceBlock.Count -gt 0) {
                    $voicePools[$speaker].Add($voiceBlock)
                    foreach ($candidate in $voiceBlock) {
                        if ($null -ne $candidate -and $candidate.PSObject.Properties.Name -contains 'voice' -and $candidate.voice) {
                            $voiceById[$speaker][[string]$candidate.voice] = $candidate
                        }
                    }
                }
            }
        }
    }
}
foreach ($character in $voicedCharacters) {
    if ($voicePools[$character].Count -eq 0) {
        throw "No native voice cues were found for $character."
    }
}

$builtScenarios = [ordered]@{}
$sceneResourceTemplates = [ordered]@{}
for ($sceneIndex = 0; $sceneIndex -lt $project.scenes.Count; $sceneIndex++) {
    $definition = $project.scenes[$sceneIndex]
    $pageCount = $definition.pages.Count
    if ($pageCount -lt 1) {
        throw "Scene $($definition.id) must contain at least one dialogue page."
    }
    $spec = $templateSpecs[$definition.id]
    $templateRoot = $templateRoots[$spec.storage]
    $matchingScenes = @($templateRoot.scenes | Where-Object { $_.label -eq $spec.target })
    $blankMode = $null -ne $spec.PSObject.Properties['mode'] -and [string]$spec.mode -eq 'blank'
    if ($matchingScenes.Count -ne 1) {
        throw "Template $($spec.storage) $($spec.target) was not found exactly once."
    }
    if (-not $blankMode -and $matchingScenes[0].texts.Count -ne $pageCount) {
        throw "Template $($spec.storage) $($spec.target) does not contain exactly $pageCount dialogue pages."
    }

    $scenario = Copy-JsonObject $templateRoot
    $selectedScene = Copy-JsonObject $matchingScenes[0]
    $scenario.scenes = [object[]]@($selectedScene)
    $scenario.name = "$($definition.id).ks"
    $scenario.hash = Get-Md5Hex $scenario.name
    $scene = $scenario.scenes[0]
    $scene.label = '*start'
    $scene.title = $definition.title
    if ($blankMode) {
        $prototypeTexts = @($scene.texts)
        if ($prototypeTexts.Count -lt 1) {
            throw "Blank scene template $($spec.storage) $($spec.target) has no native text prototype."
        }
        $expandedTexts = [Collections.Generic.List[object]]::new()
        $prototypeText = Copy-JsonObject $prototypeTexts[0]
        for ($pageIndex = 0; $pageIndex -lt $pageCount; $pageIndex++) {
            [void]$expandedTexts.Add((Copy-JsonObject $prototypeText))
        }
        $scene.texts = [object[]]$expandedTexts.ToArray()
        New-BlankSceneTimeline $scene $pageCount
    }
    if ($null -ne $definition.PSObject.Properties['presentation']) {
        Set-Presentation $scene $definition.presentation
    }
    $speakerNames = [Collections.Generic.List[string]]::new()
    for ($pageIndex = 0; $pageIndex -lt $pageCount; $pageIndex++) {
        $page = $definition.pages[$pageIndex]
        $speaker = [string]$page.speaker
        $body = [string]$page.text
        if ([string]::IsNullOrWhiteSpace($body)) {
            throw "Scene $($definition.id), page $($pageIndex + 1) is empty."
        }
        $speakerNames.Add($speaker)
        $nativeText = $scene.texts[$pageIndex]
        $nativeText[0] = $speaker
        $nativeText[1][0][0] = $null
        $nativeText[1][0][1] = $body
        $nativeText[1][0][2] = $body.Length
        if ($nativeText.Count -ge 5 -and $null -ne $nativeText[4] -and
            $null -ne $nativeText[4].PSObject.Properties['msgwin']) {
            $nativeText[4].msgwin = Get-PageMessageWindowType $page
        }
        if ($speaker -in $voicedCharacters) {
            $pool = $voicePools[$speaker]
            $requestedVoiceId = if ($null -ne $page.PSObject.Properties['voiceId']) { [string]$page.voiceId } else { '' }
            if ($requestedVoiceId) {
                if (-not $voiceById[$speaker].ContainsKey($requestedVoiceId)) {
                    throw "Scene $($definition.id), page $($pageIndex + 1) requests voiceId '$requestedVoiceId' for '$speaker', but that cue was not found in the decompiled scenario tree."
                }
                $nativeText[2] = [object[]]@(Copy-JsonObject $voiceById[$speaker][$requestedVoiceId])
            } else {
                $selection = ($sceneIndex * 31 + $pageIndex * 17 + $body.Length) % $pool.Count
                $nativeText[2] = [object[]]@($pool[$selection] | ForEach-Object { Copy-JsonObject $_ })
            }
        } else {
            $nativeText[2] = $null
        }
    }
    if ($null -ne $definition.PSObject.Properties['presentation']) {
        Set-SpeakerFocusTimeline $scene $definition.presentation ([object[]]@($definition.pages))
    }
# Speaker-focus scenes already define their names and modes; only native
# templates need the legacy name-replacement walk.
    if ($null -eq $definition.PSObject.Properties['presentation']) {
        $displayIndex = 0
        Set-DialogueLineNames $scene.lines $speakerNames.ToArray() ([ref]$displayIndex)
        if ($displayIndex -ne $pageCount) {
            throw "Template $($spec.storage) exposed $displayIndex dialogue commands for $pageCount pages."
        }
    }
    if ($null -ne $definition.PSObject.Properties['next'] -and $null -ne $definition.next) {
        $scene.nexts = [object[]]@(New-SceneEdge $definition.next)
    } else {
        $scene.nexts = $null
        if ($null -ne $scene.PSObject.Properties['postevals']) { $scene.postevals = @() }
    }
    $builtScenarios[$definition.id] = Copy-JsonObject $scenario
    $resourceTemplate = Join-Path $baseScenarioRootResolved "$($spec.storage).scn.m.resx.json"
    $sceneResourceTemplates[$definition.id] = $resourceTemplate
    Compile-Scenario $scenario (Join-Path $normalMiniRoot "$($definition.id).ks.scn.m.json") `
        (Join-Path $normalScenarioRoot "$($definition.id).ks.scn.m") $resourceTemplate
}

$injectionOverrides = [ordered]@{}
$injectionSceneListEntries = [Collections.Generic.List[object]]::new()
foreach ($injection in $project.injections) {
    $injectionKind = if ($null -ne $injection.PSObject.Properties['kind']) {
        [string]$injection.kind
    } else {
        'edge'
    }
    $sourceStorage = [string]$injection.source.storage
    if ($null -eq $injectionOverrides[$sourceStorage]) {
        $cozJson = Join-Path $sourceArchiveDir "scenario\$sourceStorage.scn.m.json"
        $baseJson = Join-Path $baseScenarioRootResolved "$sourceStorage.scn.m.json"
        if (Test-Path -LiteralPath $cozJson -PathType Leaf) {
            $sourceJson = $cozJson
        } elseif (Test-Path -LiteralPath $baseJson -PathType Leaf) {
            $sourceJson = $baseJson
        } else {
            throw "Injection source scenario is missing: $sourceStorage"
        }
        $sourceResx = $sourceJson -replace '\.json$', '.resx.json'
        if (-not (Test-Path -LiteralPath $sourceResx -PathType Leaf)) {
            throw "Injection source resources are missing: $sourceResx"
        }
        $injectionOverrides[$sourceStorage] = [pscustomobject]@{
            scenario = (Get-Content -LiteralPath $sourceJson -Raw | ConvertFrom-Json)
            resources = $sourceResx
        }
    }
    $override = $injectionOverrides[$sourceStorage]
    $sourceScenes = @($override.scenario.scenes | Where-Object { $_.label -eq $injection.source.target })
    if ($sourceScenes.Count -ne 1) {
        throw "Injection $($injection.id) did not resolve one source label."
    }
    $sourceScene = $sourceScenes[0]
    if ($null -eq $sourceScene.PSObject.Properties['nexts'] -or $null -eq $sourceScene.nexts) {
        throw "Injection $($injection.id) expected a next edge, but the source has none."
    }
    $edges = [object[]]@($sourceScene.nexts)
    $matchIndex = Get-UniqueSceneEdgeIndex $edges $injection.expectedNext "Injection $($injection.id)"
    if ($injectionKind -eq 'edge') {
        $edges[$matchIndex] = New-SceneEdge $injection.destination
        $sourceScene.nexts = [object[]]$edges
        continue
    }
    if ($injectionKind -ne 'afterLine') {
        throw "Injection $($injection.id) has unsupported kind '$injectionKind'."
    }
    if ($null -eq $sourceScene.PSObject.Properties['texts'] -or $null -eq $sourceScene.texts) {
        throw "Injection $($injection.id) cannot match a line because the source label has no dialogue table."
    }
    $matchText = [string]$injection.line.text
    $matchSpeaker = if ($null -ne $injection.line.PSObject.Properties['speaker']) {
        [string]$injection.line.speaker
    } else {
        $null
    }
    $matchContext = "Injection $($injection.id) in $sourceStorage $($injection.source.target)"
    $nativeTextNumber = 1 + (Get-UniqueDialogueTextIndex ([object[]]@($sourceScene.texts)) $matchText $matchSpeaker $matchContext)
    $splitIndex = Get-UniqueDisplayInstructionIndex ([object[]]@($sourceScene.lines)) $nativeTextNumber "Injection $($injection.id)"
    if ($splitIndex -ge $sourceScene.lines.Count - 1) {
        throw "Injection $($injection.id) cannot split after the final scenario instruction; use an edge injection instead."
    }
    $resumeTarget = [string]$injection.resumeTarget
    if ([string]::IsNullOrWhiteSpace($resumeTarget) -or -not $resumeTarget.StartsWith('*')) {
        throw "Injection $($injection.id) requires a resumeTarget beginning with *."
    }
    if (@($override.scenario.scenes | Where-Object { $_.label -eq $resumeTarget }).Count -ne 0) {
        throw "Injection $($injection.id) resume target already exists: $sourceStorage $resumeTarget"
    }

    $destinationSceneId = ([string]$injection.destination.storage) -replace '\.ks$', ''
    $destinationDefinitions = @($project.scenes | Where-Object { $_.id -eq $destinationSceneId })
    if ($destinationDefinitions.Count -ne 1 -or
        $null -eq $destinationDefinitions[0].PSObject.Properties['next'] -or
        $null -eq $destinationDefinitions[0].next -or
        [string]$destinationDefinitions[0].next.storage -ne $sourceStorage -or
        [string]$destinationDefinitions[0].next.target -ne $resumeTarget) {
        throw "Injection $($injection.id) destination must be a generated scene whose next edge returns to $sourceStorage $resumeTarget."
    }

    $continuation = Copy-JsonObject $sourceScene
    $prefixLines = [Collections.Generic.List[object]]::new()
    $suffixLines = [Collections.Generic.List[object]]::new()
    for ($lineIndex = 0; $lineIndex -lt $sourceScene.lines.Count; $lineIndex++) {
        if ($lineIndex -le $splitIndex) {
            $prefixLines.Add((Copy-JsonObject $sourceScene.lines[$lineIndex]))
        } else {
            $suffixLines.Add((Copy-JsonObject $sourceScene.lines[$lineIndex]))
        }
    }
    $prefixCheckpointMax = 0L
    foreach ($instruction in $prefixLines) {
        if ($instruction -is [System.Collections.IList] -and $instruction.Count -gt 0 -and
            ($instruction[0] -is [int] -or $instruction[0] -is [long])) {
            $prefixCheckpointMax = [Math]::Max($prefixCheckpointMax, [long]$instruction[0])
        }
    }
    if ($prefixCheckpointMax -lt 1) {
        throw "Injection $($injection.id) could not find a prefix checkpoint."
    }
    $continuationCheckpointMax = 0L
    foreach ($instruction in $suffixLines) {
        if ($instruction -is [System.Collections.IList] -and $instruction.Count -gt 0 -and
            ($instruction[0] -is [int] -or $instruction[0] -is [long])) {
            $instruction[0] = [long]$instruction[0] - $prefixCheckpointMax
            if ([long]$instruction[0] -lt 1) {
                throw "Injection $($injection.id) produced an invalid continuation checkpoint."
            }
            $continuationCheckpointMax = [Math]::Max($continuationCheckpointMax, [long]$instruction[0])
        }
    }
    if ($continuationCheckpointMax -lt 1) {
        throw "Injection $($injection.id) continuation has no checkpoint."
    }

    $continuation.label = $resumeTarget
    $continuation.firstLine = [long]$sourceScene.firstLine + $prefixCheckpointMax
    $continuation.spCount = $continuationCheckpointMax
    $continuation.lines = [object[]]$suffixLines.ToArray()
    $sourceScene.lines = [object[]]$prefixLines.ToArray()
    $sourceScene.spCount = $prefixCheckpointMax
    $sourceScene.nexts = [object[]]@(New-SceneEdge $injection.destination)
    if ($null -ne $sourceScene.PSObject.Properties['postevals']) { $sourceScene.postevals = @() }
    $override.scenario.scenes = [object[]]@($override.scenario.scenes) + $continuation
    $injectionSceneListEntries.Add([pscustomobject]@{
        selects = $null
        storage = $sourceStorage
        target = $resumeTarget
        textCount = $continuation.texts.Count
        title = [string]$continuation.title
    })
}
foreach ($property in $injectionOverrides.GetEnumerator()) {
    $storage = [string]$property.Key
    $override = $property.Value
    if (Test-Path -LiteralPath (Join-Path $normalScenarioRoot "$storage.scn.m")) {
        throw "An injection override collides with a generated scene: $storage"
    }
    Compile-Scenario $override.scenario (Join-Path $normalMiniRoot "$storage.scn.m.json") `
        (Join-Path $normalScenarioRoot "$storage.scn.m") $override.resources
}

$sceneList = Get-Content -LiteralPath $sceneListSourceJson -Raw | ConvertFrom-Json
$sceneListEntries = @($project.scenes | ForEach-Object {
    [pscustomobject]@{
        selects = $null
        storage = "$($_.id).ks"
        target = '*start'
        textCount = $_.pages.Count
        title = $_.title
    }
}) + @($injectionSceneListEntries)
foreach ($entry in $sceneListEntries) {
    $mapKey = "$($entry.storage)$($entry.target)"
    if ($null -ne $sceneList.map.PSObject.Properties[$mapKey]) {
        throw "The scene registry already contains $mapKey."
    }
    $entryIndex = $sceneList.list.Count
    $sceneList.list = @($sceneList.list) + $entry
    $sceneList.map | Add-Member -NotePropertyName $mapKey -NotePropertyValue $entryIndex
}
Compile-Scenario $sceneList (Join-Path $normalMiniRoot 'scenelist.scn.m.json') `
    (Join-Path $normalScenarioRoot 'scenelist.scn.m') $sceneListSourceResources

# Fan mode changes one scenario index for the launcher session.
$aliasSourceId = [string]$project.launchAlias.sourceScene
$aliasStorage = [string]$project.launchAlias.storage
$alias = Copy-JsonObject $builtScenarios[$aliasSourceId]
if ($null -eq $alias) { throw "Launch alias source scene does not exist: $aliasSourceId" }
$alias.name = $aliasStorage
$alias.hash = [string]$project.launchAlias.internalHash
Compile-Scenario $alias (Join-Path $fanMiniRoot "$aliasStorage.scn.m.json") `
    (Join-Path $fanScenarioRoot "$aliasStorage.scn.m") $sceneResourceTemplates[$aliasSourceId]

$fanSceneList = Copy-JsonObject $sceneList
$gameStartEntries = @($fanSceneList.list | Where-Object { $_.storage -eq $aliasStorage -and $_.target -eq '*start' })
if ($gameStartEntries.Count -ne 1) {
    throw "Expected exactly one ac_00_01.ks *start registry entry; found $($gameStartEntries.Count)."
}
$aliasSourceDefinition = @($project.scenes | Where-Object { $_.id -eq $aliasSourceId })[0]
$gameStartEntries[0].textCount = $aliasSourceDefinition.pages.Count
$gameStartEntries[0].title = $aliasSourceDefinition.title
Compile-Scenario $fanSceneList (Join-Path $fanMiniRoot 'scenelist.scn.m.json') `
    (Join-Path $fanScenarioRoot 'scenelist.scn.m') $sceneListSourceResources

Pack-MiniArchive $normalMiniRoot
Pack-MiniArchive $fanMiniRoot

$finalBody = Join-Path $outputRootResolved 'c0patch_body.bin'
Copy-Item -LiteralPath $sourceBody -Destination $finalBody
$baseLength = (Get-Item -LiteralPath $finalBody).Length
$normalMiniBody = Join-Path $normalMiniRoot 'c0patch_body.bin'
$fanMiniBody = Join-Path $fanMiniRoot 'c0patch_body.bin'
$normalMiniLength = (Get-Item -LiteralPath $normalMiniBody).Length
$fanModeBaseOffset = [long]$baseLength + [long]$normalMiniLength
$bodyStream = [IO.File]::Open($finalBody, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    foreach ($appendPath in @($normalMiniBody, $fanMiniBody)) {
        $appendBytes = [IO.File]::ReadAllBytes($appendPath)
        $bodyStream.Write($appendBytes, 0, $appendBytes.Length)
    }
} finally {
    $bodyStream.Dispose()
}

$normalManifest = Get-Content -LiteralPath $sourceManifest -Raw | ConvertFrom-Json
$packedNormalManifest = Get-Content -LiteralPath (Join-Path $normalMiniRoot 'c0patch_info.psb.m.json') -Raw | ConvertFrom-Json
foreach ($property in $packedNormalManifest.file_info.PSObject.Properties) {
    $entry = @(([long]$baseLength + [long]$property.Value[0]), [long]$property.Value[1])
    if ($null -ne $normalManifest.file_info.PSObject.Properties[$property.Name]) {
        $normalManifest.file_info.PSObject.Properties[$property.Name].Value = $entry
    } else {
        $normalManifest.file_info | Add-Member -NotePropertyName $property.Name -NotePropertyValue $entry
    }
}

$fanManifest = Copy-JsonObject $normalManifest
$packedFanManifest = Get-Content -LiteralPath (Join-Path $fanMiniRoot 'c0patch_info.psb.m.json') -Raw | ConvertFrom-Json
foreach ($property in $packedFanManifest.file_info.PSObject.Properties) {
    $entry = @(([long]$fanModeBaseOffset + [long]$property.Value[0]), [long]$property.Value[1])
    if ($null -eq $fanManifest.file_info.PSObject.Properties[$property.Name]) {
        throw "Fan-mode overlay attempted to replace an unknown base entry: $($property.Name)"
    }
    $fanManifest.file_info.PSObject.Properties[$property.Name].Value = $entry
}

$normalInfo = Join-Path $outputRootResolved 'c0patch_info.normal.psb.m'
$fanInfo = Join-Path $outputRootResolved 'c0patch_info.fan.psb.m'
Compile-Index $normalManifest (Join-Path $outputRootResolved 'index-normal') $normalInfo
Compile-Index $fanManifest (Join-Path $outputRootResolved 'index-fan') $fanInfo

foreach ($requiredOutput in @($normalInfo, $fanInfo, $finalBody)) {
    if (-not (Test-Path -LiteralPath $requiredOutput -PathType Leaf)) {
        throw "Expected rebuilt archive is missing: $requiredOutput"
    }
}
Write-Host "Built normal and temporary fan-mode indexes in $outputRootResolved"
