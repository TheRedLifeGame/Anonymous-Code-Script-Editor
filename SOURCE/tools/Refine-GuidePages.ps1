[CmdletBinding()]
param(
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..\project.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-Page([string]$Speaker, [string]$Text, [string]$VoiceId = '') {
    $page = [ordered]@{ speaker = $Speaker }
    if (-not [string]::IsNullOrWhiteSpace($VoiceId)) { $page.voiceId = $VoiceId }
    $page.text = $Text
    return [pscustomobject]$page
}

$projectPathResolved = (Resolve-Path -LiteralPath $ProjectPath).Path
$project = Get-Content -LiteralPath $projectPathResolved -Raw | ConvertFrom-Json
$scene = @($project.scenes | Where-Object id -eq 'ac_ex_guide')[0]
if ($null -eq $scene) { throw 'ac_ex_guide scene was not found.' }
if ($scene.pages.Count -eq 65) {
# Safe to rerun after the guide has been expanded.
    $voiceAdjust = @{
        7 = 'ac_01_02_crs0010'
        11 = 'ac_01_04_pol0002'
        13 = 'ac_02_13_crs0008'
        12 = 'ac_01_02_pol0032'
        21 = 'ac_01_04_win0013'
        22 = 'ac_01_04_win0013'
        30 = 'ac_01_04_win0029'
        31 = 'ac_01_02_pol0005'
        36 = 'ac_00_01_pol0011'
        45 = 'ac_01_07_mom0038'
        48 = 'ac_00_01_pol0011'
        52 = 'ac_03_05_win0002'
        63 = 'ac_01_07_pol0042'
        64 = 'ac_01_02_pol0021'
    }
    foreach ($position in $voiceAdjust.Keys) { $scene.pages[$position - 1].voiceId = $voiceAdjust[$position] }
    $project | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $projectPathResolved -Encoding utf8
    Write-Host 'Adjusted voice timing for the already-expanded 65-page guide.' -ForegroundColor Green
    exit 0
}
if ($scene.pages.Count -ne 31) { throw "Expected the original 31-page guide, found $($scene.pages.Count)." }

# Match voice selection to each line's tone and timing notes.
$pages = @{}
$pages[1] = @(New-Page '' 'WELCOME TO THE ANONYMOUS;CODE PATCHING GUIDE'; New-Page '' 'You will be guided through the developer project included with the patch.')
$pages[2] = @(New-Page 'ポロン' "Yo, Anon. If you're seeing this, your custom scenario compiled and loaded." 'ac_09_06_pol0006'; New-Page 'ポロン' 'Heh. Not bad, right?' 'ac_00_01_pol0016')
$pages[3] = @(New-Page 'ウインド' "WOOOO! THEY MADE IT IN! Takaoka, our newest anon's alive! That's sick!" 'ac_02_17_win0012')
$pages[4] = @(New-Page 'クロス' "You're celebrating a little early." 'ac_01_03_crs0003'; New-Page 'クロス' "Anon, open the release's SOURCE folder. Read DEVELOPER-GUIDE.md, then open project.json." 'ac_01_02_crs0010')
$pages[5] = @(New-Page 'モモ' "Umm...please don't let them overwhelm you." 'ac_01_07_mom0034'; New-Page 'モモ' 'Keeping the guide open while you work should make the rest much easier to follow.' 'ac_01_07_mom0038')
$pages[6] = @(New-Page 'ポロン' "C'mon, we're not that bad." 'ac_00_01_pol0016'; New-Page 'ポロン' 'Anyway, project.json is where you set up your generated scenes—what they show,' 'ac_02_03_pol0024'; New-Page 'ポロン' 'what they say, and where they go.' 'ac_01_02_pol0002')
$pages[7] = @(New-Page 'クロス' 'More precisely: generated scenes, presentation data, next edges, and story injections.' 'ac_07_20_crs0006')
$pages[8] = @(New-Page 'モモ' "Please use the engine's Japanese speaker keys exactly as they appear." 'ac_04_03_mom0005'; New-Page 'モモ' "For us, that's ポロン, モモ, クロス, and ウインド." 'ac_01_07_mom0013')
$pages[9] = @(New-Page 'ポロン' "Yeah, copy 'em. Don't make any lookalikes, Anon." 'ac_01_02_pol0005'; New-Page 'ポロン' 'And an empty speaker string means narration. No name in the message box.' 'ac_02_03_pol0024')
$pages[10] = @(New-Page 'モモ' 'speakerGroups controls which configured characters remain visible for each speaker.' 'ac_05_14_mom0008'; New-Page 'モモ' "It can also keep a first-person speaker's own sprite hidden." 'ac_01_07_mom0038')
$pages[11] = @(New-Page 'ウインド' 'And voiceCharacters lets you reuse matching Japanese voice cues already installed by the game!' 'ac_01_04_win0011'; New-Page 'ウインド' "The patch itself doesn't ship extra audio, though." 'ac_01_04_win0013'; New-Page 'ウインド' 'No free game assets, sorryyy!' 'ac_01_04_win0013')
$pages[12] = @(New-Page 'クロス' 'Before you inject anything into the real story, inspect the route first.' 'ac_01_02_crs0010'; New-Page 'クロス' 'Run tools/Inspect-Scenario.ps1 on the decompiled scenario.' 'ac_07_19_crs0009')
$pages[13] = @(New-Page 'ポロン' "It'll give ya the labels, dialogue, speakers, counts, and outgoing edges." 'ac_02_03_pol0024'; New-Page 'ポロン' 'Trust me, guessing is how it becomes a shitshow.' 'ac_00_01_pol0026')
$pages[14] = @(New-Page 'クロス' 'Crude, but correct. Verify the exact target before you edit it.' 'ac_10_07_crs0002')
$pages[15] = @(New-Page 'モモ' "If you're only testing a scene, you don't need an injection at all." 'ac_01_07_mom0034'; New-Page 'モモ' 'Set launchAlias.sourceScene to its id, run the fan launcher, and choose GAME START.' 'ac_04_03_mom0005')
$pages[16] = @(New-Page 'ウインド' 'Boom! Straight into your scene! Great for testing and navigating.' 'ac_02_17_win0012')
$pages[17] = @(New-Page 'ポロン' 'For the real story, use an edge injection.' 'ac_02_03_pol0024'; New-Page 'ポロン' 'You replace one verified label-to-label transition with your custom scene.' 'ac_01_02_pol0005')
$pages[18] = @(New-Page 'クロス' 'source selects the existing storage and label.' 'ac_01_02_crs0022'; New-Page 'クロス' 'expectedNext proves the original route is still what you inspected.' 'ac_05_10_crs0002'; New-Page 'クロス' 'If it changed, let the build fail.' 'ac_01_02_crs0004')
$pages[19] = @(New-Page 'ポロン' "In other words: don't bulldoze through a safety check just 'cause you're impatient, Anon." 'ac_00_01_pol0026')
$pages[20] = @(New-Page 'モモ' 'destination is your branch.' 'ac_01_07_mom0013'; New-Page 'モモ' 'Then point your generated scene''s next edge to the displaced original destination,' 'ac_05_14_mom0008'; New-Page 'モモ' 'and the base story can resume.' 'ac_01_07_mom0038')
$pages[21] = @(New-Page 'ウインド' "Need to cut in at one exact line instead? That's afterLine!" 'ac_02_17_win0006'; New-Page 'ウインド' 'One exact speaker, one exact line, then—bam!—your scene branches right after it.' 'ac_01_04_win0011')
$pages[22] = @(New-Page 'クロス' 'The match has to be unique and case-exact.' 'ac_01_02_crs0016'; New-Page 'クロス' 'expectedNext still applies.' 'ac_01_02_crs0021'; New-Page 'クロス' 'The builder creates a resumeTarget for the continuation.' 'ac_07_19_crs0009')
$pages[23] = @(New-Page 'モモ' 'Your inserted scene should point next to that resumeTarget.' 'ac_05_14_mom0008'; New-Page 'モモ' 'That allows the original animation state and downstream edge to continue normally.' 'ac_01_07_mom0038')
$pages[24] = @(New-Page 'ポロン' 'And use unique ac_ex_ ids and unique resume labels.' 'ac_01_02_pol0005'; New-Page 'ポロン' "Don't go stepping on ids unless you're deliberately making an override." 'ac_00_01_pol0026')
$pages[25] = @(New-Page 'クロス' 'The installer also checks for the exact archive hashes it targets.' 'ac_05_10_crs0002'; New-Page 'クロス' 'Uninstall restores the backup.' 'ac_01_02_crs0004')
$pages[26] = @(New-Page 'ウインド' "You've got startup, edge-injection, and after-line examples right beside the guide!" 'ac_01_04_win0011'; New-Page 'ウインド' 'Copy one, change one thing, test it, repeat.' 'ac_01_04_win0018'; New-Page 'ウインド' 'Future-you will be sooo grateful!' 'ac_02_17_win0012')
$pages[27] = @(New-Page 'モモ' "I think that's everything important." 'ac_01_07_mom0038'; New-Page 'モモ' 'If something doesn''t work, please check the guide and the inspector output' 'ac_05_14_mom0008'; New-Page 'モモ' 'before changing several things at once.' 'ac_01_07_mom0013')
$pages[28] = @(New-Page 'ポロン' 'Yeah. One problem at a time.' 'ac_01_07_pol0044'; New-Page "ポロン" "You've got this, Anon." 'ac_01_07_pol0044')
$pages[29] = @(New-Page 'ウインド' 'WOOO! LOOK AT TAKAOKA GIVING RESPONSIBLE ADVICE!' 'ac_02_17_win0006'; New-Page 'ウインド' 'Somebody save this moment!' 'ac_02_17_win0012')
$pages[30] = @(New-Page 'クロス' "Too late. He'll deny it happened." 'ac_01_04_crs0002')
$pages[31] = @(New-Page 'ポロン' "Shut up! We're done here!" 'ac_00_01_pol0026'; New-Page 'ポロン' 'Nakano Symphonies did its job.' 'ac_01_07_pol0044'; New-Page 'ポロン' 'Read the full guide if you need the details, Anon.' 'ac_02_17_pol0051'; New-Page 'ポロン' 'Aight—back to the title screen!' 'ac_00_01_pol0027')

$expanded = [Collections.Generic.List[object]]::new()
for ($index = 1; $index -le 31; $index++) {
    foreach ($page in @($pages[$index])) { [void]$expanded.Add($page) }
}
$scene.pages = [object[]]$expanded.ToArray()
$project | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $projectPathResolved -Encoding utf8
Write-Host "Expanded guide from 31 pages to $($scene.pages.Count) readable pages." -ForegroundColor Green
