[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioJsonRoot,

    [string]$VoiceRoot,

    [string]$PsbDecompilePath,

    [string]$OutputRoot = (Join-Path (Get-Location) 'voice-export'),

    [string[]]$Ids,

    [string]$IdFile,

    [switch]$ExtractAudio,

    [switch]$IncludeArchiveInventory,

    [switch]$ConvertWav,

    [string]$VlcPath,

    [switch]$Open,

    [int]$MaxExtract = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TextFromEntry {
    param([object]$Entry)

    $entryArray = @($Entry)
    if ($null -eq $Entry -or $entryArray.Count -lt 2 -or $null -eq $entryArray[1]) {
        return ''
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($fragment in @($entryArray[1])) {
        $fragmentArray = @($fragment)
        if ($null -ne $fragment -and $fragmentArray.Count -gt 1 -and $null -ne $fragmentArray[1]) {
            [void]$parts.Add([string]$fragmentArray[1])
        }
    }
    return ($parts -join '')
}

function Add-Occurrence {
    param(
        [hashtable]$Table,
        [string]$VoiceId,
        [string]$Speaker,
        [string]$Text,
        [string]$Scenario,
        [string]$Label,
        [int]$TextIndex,
        [int]$LineIndex,
        [object]$Block,
        [string]$SourceKind
    )

    if ([string]::IsNullOrWhiteSpace($VoiceId)) { return }
    if (-not $Table.ContainsKey($VoiceId)) {
        $Table[$VoiceId] = [ordered]@{
            id = $VoiceId
            speaker = $Speaker
            text = $Text
            durationMs = $null
            durationEnglishMs = $null
            scenarios = New-Object System.Collections.Generic.List[string]
            occurrences = New-Object System.Collections.Generic.List[object]
        }
    }

    $record = $Table[$VoiceId]
    if ([string]::IsNullOrWhiteSpace([string]$record.speaker) -and -not [string]::IsNullOrWhiteSpace($Speaker)) {
        $record.speaker = $Speaker
    }
    if ([string]::IsNullOrWhiteSpace([string]$record.text) -and -not [string]::IsNullOrWhiteSpace($Text)) {
        $record.text = $Text
    }
    if ($null -ne $Block) {
        if (($Block.PSObject.Properties.Name -contains 'time') -and $null -ne $Block.time -and $null -eq $record.durationMs) { $record.durationMs = [int]$Block.time }
        if (($Block.PSObject.Properties.Name -contains 'time_en') -and $null -ne $Block.time_en -and $null -eq $record.durationEnglishMs) { $record.durationEnglishMs = [int]$Block.time_en }
    }
    if (-not $record.scenarios.Contains($Scenario)) { [void]$record.scenarios.Add($Scenario) }
    [void]$record.occurrences.Add([ordered]@{
        scenario = $Scenario
        label = $Label
        speaker = $Speaker
        textIndex = $TextIndex
        lineIndex = $LineIndex
        text = $Text
        source = $SourceKind
    })
}

if (-not $ScenarioJsonRoot -and -not $IncludeArchiveInventory) {
    throw 'Provide -ScenarioJsonRoot, or provide -VoiceRoot with -IncludeArchiveInventory for an archive-only catalog.'
}

$scenarioFiles = @()
if ($ScenarioJsonRoot) {
    if (-not (Test-Path -LiteralPath $ScenarioJsonRoot -PathType Container)) {
        throw "ScenarioJsonRoot does not exist: $ScenarioJsonRoot"
    }
    $scenarioFiles = @(Get-ChildItem -LiteralPath $ScenarioJsonRoot -Filter '*.ks.scn.m.json' -File -Recurse)
    if ($scenarioFiles.Count -eq 0) { throw "No *.ks.scn.m.json files found under $ScenarioJsonRoot" }
}

$wanted = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($id in @($Ids)) {
    if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$wanted.Add($id.Trim()) }
}
if ($IdFile) {
    if (-not (Test-Path -LiteralPath $IdFile -PathType Leaf)) { throw "IdFile does not exist: $IdFile" }
    foreach ($line in Get-Content -LiteralPath $IdFile) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith('#')) { [void]$wanted.Add($trimmed) }
    }
}

if ($IncludeArchiveInventory) {
    if (-not $VoiceRoot) { throw '-VoiceRoot is required with -IncludeArchiveInventory' }
    if (-not (Test-Path -LiteralPath $VoiceRoot -PathType Container)) { throw "VoiceRoot does not exist: $VoiceRoot" }
}

$table = @{}
foreach ($file in $scenarioFiles) {
    $scenario = [IO.Path]::GetFileName($file.Name) -replace '\.scn\.m\.json$',''
    $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    foreach ($scene in @($json.scenes)) {
        $label = [string]$scene.label
        $textIndex = 0
        $sceneTexts = @()
        if ($scene.PSObject.Properties.Name -contains 'texts') { $sceneTexts = @($scene.texts) }
        foreach ($entry in $sceneTexts) {
            if ($null -eq $entry) { $textIndex++; continue }
            $entryArray = @($entry)
            $speaker = ''
            if ($entryArray.Count -gt 0 -and $null -ne $entryArray[0]) { $speaker = [string]$entryArray[0] }
            $text = Get-TextFromEntry $entry
            if ($entryArray.Count -gt 2 -and $null -ne $entryArray[2]) {
                foreach ($block in @($entryArray[2])) {
                    if ($null -ne $block -and $block.PSObject.Properties.Name -contains 'voice' -and $null -ne $block.voice) {
                        Add-Occurrence -Table $table -VoiceId ([string]$block.voice) -Speaker $speaker -Text $text -Scenario $scenario -Label $label -TextIndex $textIndex -LineIndex -1 -Block $block -SourceKind 'text'
                    }
                }
            }
            $textIndex++
        }

        $lineIndex = 0
        $sceneLines = @()
        if ($scene.PSObject.Properties.Name -contains 'lines') { $sceneLines = @($scene.lines) }
        foreach ($line in $sceneLines) {
            $lineArray = @($line)
            if ($null -ne $line -and $lineArray.Count -gt 0 -and [string]$lineArray[0] -eq 'playvoice') {
                $voiceId = $null
                for ($i = 1; $i -lt $lineArray.Count - 1; $i++) {
                    if ([string]$lineArray[$i] -eq 'voice') { $voiceId = [string]$lineArray[$i + 1]; break }
                }
                if ($voiceId) {
                    Add-Occurrence -Table $table -VoiceId $voiceId -Speaker '' -Text '' -Scenario $scenario -Label $label -TextIndex -1 -LineIndex $lineIndex -Block $null -SourceKind 'playvoice'
                }
            }
            $lineIndex++
        }
    }
}

if ($IncludeArchiveInventory) {
    foreach ($archive in Get-ChildItem -LiteralPath $VoiceRoot -File) {
        $voiceId = $archive.Name
        if ($table.ContainsKey($voiceId)) { continue }
        $table[$voiceId] = [ordered]@{
            id = $voiceId
            speaker = ''
            text = ''
            durationMs = $null
            durationEnglishMs = $null
            scenarios = New-Object System.Collections.Generic.List[string]
            occurrences = New-Object System.Collections.Generic.List[object]
        }
    }
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($voiceId in @($table.Keys | Sort-Object)) {
    $record = $table[$voiceId]
    $occurrences = @($record.occurrences.ToArray())
    $sourceKindsList = New-Object System.Collections.Generic.List[string]
    foreach ($occurrence in $occurrences) {
        if (-not $sourceKindsList.Contains([string]$occurrence.source)) { [void]$sourceKindsList.Add([string]$occurrence.source) }
    }
    [void]$records.Add([pscustomobject]@{
        id = $record.id
        speaker = $record.speaker
        text = $record.text
        durationMs = $record.durationMs
        durationEnglishMs = $record.durationEnglishMs
        occurrenceCount = $occurrences.Count
        scenarios = (@($record.scenarios.ToArray()) -join ';')
        firstScenario = if ($occurrences.Count) { $occurrences[0].scenario } else { '' }
        firstLabel = if ($occurrences.Count) { $occurrences[0].label } else { '' }
        sourceKinds = ($sourceKindsList -join ';')
        archiveFile = if ($VoiceRoot) { Join-Path $VoiceRoot $record.id } else { '' }
        extractedAudio = ''
        playableAudio = ''
        wavAudio = ''
        occurrencesJson = ($occurrences | ConvertTo-Json -Depth 5 -Compress)
    })
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$manifestPath = Join-Path $OutputRoot 'voice-blocks.json'
$csvPath = Join-Path $OutputRoot 'voice-blocks.csv'
$summaryPath = Join-Path $OutputRoot 'README.txt'

$allManifest = [ordered]@{
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    scenarioJsonRoot = if ($ScenarioJsonRoot) { (Resolve-Path -LiteralPath $ScenarioJsonRoot).Path } else { '' }
    voiceRoot = if ($VoiceRoot) { (Resolve-Path -LiteralPath $VoiceRoot).Path } else { '' }
    count = $records.Count
    records = $records
}
$allManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$selected = @($records | Where-Object { $wanted.Count -eq 0 -or $wanted.Contains($_.id) })
if ($wanted.Count -gt 0) {
    $missing = @($wanted | Where-Object { -not ($records.id -contains $_) })
    if ($missing.Count) { Write-Warning ("IDs not present in scenario text: " + ($missing -join ', ')) }
}

if ($ExtractAudio) {
    if (-not $VoiceRoot) { throw '-VoiceRoot is required with -ExtractAudio' }
    if (-not (Test-Path -LiteralPath $VoiceRoot -PathType Container)) { throw "VoiceRoot does not exist: $VoiceRoot" }
    if (-not $PsbDecompilePath -or -not (Test-Path -LiteralPath $PsbDecompilePath -PathType Leaf)) { throw '-PsbDecompilePath must point to FreeMote PsbDecompile.exe' }
    if ($ConvertWav) {
        if (-not $VlcPath) {
            $vlcCommand = Get-Command vlc.exe -ErrorAction SilentlyContinue
            if ($vlcCommand) { $VlcPath = $vlcCommand.Source }
            elseif (Test-Path -LiteralPath 'C:\Program Files\VideoLAN\VLC\vlc.exe') { $VlcPath = 'C:\Program Files\VideoLAN\VLC\vlc.exe' }
            elseif (Test-Path -LiteralPath 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe') { $VlcPath = 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe' }
        }
        if (-not $VlcPath -or -not (Test-Path -LiteralPath $VlcPath -PathType Leaf)) { throw '-ConvertWav requires VLC. Pass -VlcPath to vlc.exe.' }
    }
    if ($selected.Count -gt $MaxExtract) { throw "Refusing to extract $($selected.Count) IDs; MaxExtract is $MaxExtract. Pass a smaller -Ids set or raise -MaxExtract." }

    $audioRoot = [IO.Path]::GetFullPath((Join-Path $OutputRoot 'audio'))
    $playableRoot = [IO.Path]::GetFullPath((Join-Path $OutputRoot 'playable'))
    $wavRoot = [IO.Path]::GetFullPath((Join-Path $OutputRoot 'wav'))
    New-Item -ItemType Directory -Path $audioRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $playableRoot -Force | Out-Null
    if ($ConvertWav) { New-Item -ItemType Directory -Path $wavRoot -Force | Out-Null }
    foreach ($record in $selected) {
        $source = Join-Path $VoiceRoot $record.id
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            $record.archiveFile = $source
            continue
        }
        $destination = Join-Path $audioRoot $record.id
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        & $PsbDecompilePath -o $destination $source
        if ($LASTEXITCODE -ne 0) { throw "PsbDecompile failed for $($record.id) (exit $LASTEXITCODE)" }
        $audio = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object { $_.Name -like '*.xwma*' } | Select-Object -First 1)
        if ($audio.Count -eq 1) {
            $record.extractedAudio = $audio[0].FullName
            $playable = Join-Path $playableRoot ($record.id + '.wma')
            Copy-Item -LiteralPath $audio[0].FullName -Destination $playable -Force
            $record.playableAudio = $playable
            if ($ConvertWav) {
                $wav = [IO.Path]::GetFullPath((Join-Path $wavRoot ($record.id + '.wav')))
                $sout = "#transcode{acodec=s16l,channels=1,samplerate=48000}:std{access=file,mux=wav,dst='$wav'}"
                & $VlcPath '--intf=dummy' '--no-video' '--play-and-exit' "--sout=$sout" $playable 2>$null
                for ($wait = 0; $wait -lt 20 -and -not (Test-Path -LiteralPath $wav -PathType Leaf); $wait++) { Start-Sleep -Milliseconds 100 }
                if (-not (Test-Path -LiteralPath $wav -PathType Leaf)) { throw "VLC WAV conversion failed for $($record.id)" }
                $record.wavAudio = $wav
            }
        }
    }
    $allManifest.records = $records
    $allManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

@"
VOICE BLOCK EXPORT
==================
Unique voice IDs found: $($records.Count)
Selected IDs: $($selected.Count)

Use voice-blocks.csv for sorting/filtering by id, speaker, text, scenario, or duration.
Use voice-blocks.json for the full occurrence list.

When -ExtractAudio is used, playable copies are written under playable\ as .wma
files so VLC/Windows Media Player can recognize the native XWMA container. Add
-ConvertWav to create clean PCM WAV files under wav\ when native playback stutters.

To extract selected audio, rerun with:
  -Ids <id1>,<id2> -VoiceRoot <decompiled voice folder> -PsbDecompilePath <FreeMote PsbDecompile.exe> -ExtractAudio

The extracted files are the game's native XWMA containers. They are intentionally not
redistributed by the patch; this export is for the owner of the installed game.
"@ | Set-Content -LiteralPath $summaryPath -Encoding UTF8

if ($Open) {
    $openable = @($selected | Where-Object {
        ($_.wavAudio -and (Test-Path -LiteralPath $_.wavAudio -PathType Leaf)) -or
        ($_.playableAudio -and (Test-Path -LiteralPath $_.playableAudio -PathType Leaf))
    })
    if ($openable.Count -eq 0) { throw '-Open requires -ExtractAudio and at least one successfully extracted ID' }
    $openPath = if ($openable[0].wavAudio -and (Test-Path -LiteralPath $openable[0].wavAudio -PathType Leaf)) { $openable[0].wavAudio } else { $openable[0].playableAudio }
    Start-Process -FilePath $openPath
}

Write-Output "Wrote $($records.Count) unique voice IDs to $manifestPath and $csvPath"
if ($ExtractAudio) { Write-Output "Extracted $((@($selected | Where-Object { $_.extractedAudio })).Count) selected audio container(s) under $(Join-Path $OutputRoot 'audio')" }
