# ANONYMOUS;CODE custom-scene developer guide

Hi! Thank you for downloading my tool. Here's how to actually use it.

The included `project.json` is a tutorial. It sends GAME START to it; the normal story is left alone. The files in `examples` show the other entry points.

## Before you start

- The project does not distribute game voice, sprite, background, music, movie, or motion assets.
- Generated scenes reference assets already installed by the game.
- A native template is executable presentation data, not just a visual sample. Blank mode keeps a small native message shell and takes its page count from your project. It has been tested with 1,000 pages.
- You should have the CoZ patch installed.
- Back up saves and keep the game closed while installing, uninstalling, or swapping archive indexes.
- This is an unofficial fan project and is not affiliated with MAGES., Spike Chunsoft, or any other developers.

## Local-only setup

You will need to choose your own game files.

- choose the game directory on the editor's Project tab;
- let the editor derive its disposable scenario cache from the installed c0patch, or set `AC_EXTRACT_ROOT` and `AC_SCENARIO_JSON_ROOT` if you maintain the extracted files yourself;
- keep those roots outside the release package and refresh the asset index after adding local files.

The editor still opens and edits `project.json` without a game or scenario root, but the Game browser and template-label lists will be empty. The generated cache lives under `%LOCALAPPDATA%\\A-C Script Studio\\game-cache`, outside the package. Basically, if you want to actually use the editor, you need the required tools and files.

## Project layout

| Path | Purpose |
| --- | --- |
| `project.json` | The active scene project. |
| `Editor/ac_script_editor.py` | Windows editor for editing, validating, building, and browsing assets. Start it with `..\Launch Editor.cmd`. |
| `scene-project.schema.json` | JSON Schema for project files. |
| `build.ps1` | Compiles generated scenes, scenario overrides, registry entries, and the normal/custom indexes. |
| `Build/ScenarioBuild.psm1` | Deterministic build and injection helpers used by the compiler and regression tests. |
| `tests/` | Dependency-free Python and PowerShell regression tests. |
| `tools/Inspect-Scenario.ps1` | Lists labels, page counts, outgoing edges, speakers, and exact dialogue in one decompiled scenario. |
| `tools/List-Speakers.ps1` | Counts every internal speaker key across a decompiled scenario tree. |
| `tools/Extract-VoiceBlocks.ps1` | Catalogs voice IDs with speaker/text/timing context and extracts selected local voice containers for playback. |
| `tools/Refine-GuidePages.ps1` | Splits the tutorial into short same-speaker pages and reapplies its voice cues. |
| `examples/startup-alias.json` | GAME START custom-session entry example. |
| `examples/edge-injection.json` | Branch at the end of a specific native label. |
| `examples/after-line-injection.json` | Branch immediately after one exact spoken line and later resume. |

## Engine and archive entry points

The game keeps the patch in two files under `windata`:

- `c0patch_info.psb.m` is the index. It maps archive paths to offsets and lengths.
- `c0patch_body.bin` is the data body containing CoZ files and appended custom entries.

Scenario archive entries are stored under `scenario/` and normally use names such as `ac_04_05.ks.scn.m`. The global `scenario/scenelist.scn.m` has two equally important structures:

- `list` stores ordered scene metadata: storage, target, title, and text count.
- `map` maps the exact concatenation `storage + target` to the matching list index.

A new scene or generated continuation must be added to both structures. A list entry without a matching map entry may work once, then fail on the next lookup and send the game back to the title while it saves system data. `build.ps1` updates both.

`build.ps1` creates one append-only body and two indexes:

- `c0patch_info.normal.psb.m` keeps ordinary CoZ GAME START behavior and includes enabled normal-story injections.
- `c0patch_info.fan.psb.m` temporarily overlays the GAME START scenario with `launchAlias.sourceScene`.
- `c0patch_body.bin` is shared by both indexes.

The launcher writes the custom indexes for one process session, starts `game.exe`, waits for it to close, and restores the verified normal index. Starting the installer or launcher again also recovers an interrupted session. The editor allows you to permanently install the patch or uninstall it. 

## Build inputs and command

`build.ps1` takes five parameters:

| Parameter | Required | Meaning |
| --- | --- | --- |
| `ExtractRoot` | Yes | Extracted CoZ archive root containing `c0patch`, `c0patch_body.bin`, and the decompiled archive manifest/resources. |
| `ToolRoot` | Yes | User-provided tool folder containing `FreeMote/PsBuild.exe` and `FreeMote/PsbDecompile.exe`; this editor does not redistribute those tools. |
| `BaseScenarioJsonRoot` | Yes | Decompiled retail scenario JSON and matching `.resx.json` files. |
| `OutputRoot` | Yes | A new disposable build directory. Existing outputs under the fan-patch work area may be replaced. |
| `ProjectPath` | No | Alternate project JSON. Defaults to the `project.json` beside `build.ps1`. |

Example from this workspace:

```powershell
& .\build.ps1 `
  -ExtractRoot '..\coz-extract' `
  -ToolRoot '..\external-tools' `
  -BaseScenarioJsonRoot '..\base-scenario-json' `
  -OutputRoot '..\guide-build'
```

To build an experiment without replacing the active project:

```powershell
& .\build.ps1 `
  -ExtractRoot '..\coz-extract' `
  -ToolRoot '..\external-tools' `
  -BaseScenarioJsonRoot '..\base-scenario-json' `
  -OutputRoot '..\line-test-build' `
  -ProjectPath '.\my-line-test.json'
```

It works from scenarios from your current game install and does nessecary work to decompile and get them working.

## `project.json` top level

```json
{
  "schemaVersion": 2,
  "metadata": {},
  "voiceCharacters": [],
  "launchAlias": {},
  "scenes": [],
  "injections": []
}
```

### `schemaVersion`

Use `2` for line-level injection support. 

### `metadata`

- `title`: human-readable project title.
- `version`: release or experiment version.
- `continuity`: optional note about where the material belongs in the story.

Metadata does not choose an engine entry point.

### `voiceCharacters`

List exact internal Japanese speaker keys here. When a generated page uses one, the build selects a Japanese voice block for that character from the template scenario files.

Keep in mind:

- The cue is character-matched but not dialogue-matched.
- No audio is copied into the patch.
- If a listed key has no voice cues anywhere in the selected template scenario files, the build fails.
- A speaker omitted from `voiceCharacters` still gets a name box but no injected voice cue.
- `"speaker": ""` is narration.

### `launchAlias`

```json
{
  "storage": "ac_00_01.ks",
  "sourceScene": "ac_ex_guide",
  "internalHash": "dab8b2d721f84912083080dca0aeef59"
}
```

- `storage` is the existing scenario temporarily replaced in the fan index. For this game it is `ac_00_01.ks`, the GAME START entry.
- `sourceScene` is one generated scene id from `scenes`.
- `internalHash` is the original scenario's engine hash and must remain the known value unless a different executable build is deliberately targeted.

This entry exists only in the temporary fan index, so it is useful for testing without changing ordinary story flow.

## Defining a generated scene

```json
{
  "id": "ac_ex_example",
  "title": "MY CUSTOM SCENE",
  "template": {
    "storage": "ac_04_05.ks",
    "target": "*chk"
  },
  "next": {
    "storage": "ac_04_05.ks",
    "target": "*next_label"
  },
  "pages": [
    { "speaker": "ポロン", "text": "First page." }
  ]
}
```

### `id`

- The build creates `<id>.ks.scn.m` and registers `<id>.ks*start`.
- Prefix extension work with `ac_ex_` to reduce collision risk.
- Every id must be unique and must not already exist in the installed archive.

### `title`

This goes into the generated scene and scene registry. 

### `template`

`storage` and `target` select one native label from the decompiled retail scenarios. In the default `native` mode, the build copies that label's:

- background and event-image state;
- live character sprite/motion timeline;
- music and sound-effect commands;
- message timing and transitions;
- save/checkpoint structure;
- exact number of dialogue display slots.

The build replaces dialogue bodies, name-box values, and selected voice blocks. It leaves the native sprite choreography intact. If Momo speaks on a page whose template shows Cross, the name and voice can say Momo while Cross stays on screen. Pick a template with a similar cast and pace. However, the template setup is very useful for having visuals being displayed or quick edits to the script.

Set `mode` to `blank` when the scene should have an arbitrary page count:

```json
"template": {
  "storage": "ac_03_20.ks",
  "target": "*flashback_1",
  "mode": "blank"
}
```

Blank mode uses the selected label only as a native message/checkpoint shell. It generates one text entry and one dialogue checkpoint per `pages` entry, so the page count no longer has to match the shell label. Each non-final checkpoint links to the following text number and message mode; the final checkpoint terminates that chain, and the closing state checkpoint is assigned an ID beyond all generated text checkpoints. These links are required by the runtime even though an unlinked JSON file can still compile successfully. `presentation.speakerFocus` is recommended because it removes the shell's inherited CG, camera, effects, and character choreography. The shell still supplies the engine's message window, input, save/backlog, and archive metadata structures.

The active tutorial uses `ac_03_20.ks *flashback_1`: 24 dialogue pages and native timelines containing Pollon, Momo, Cross, and Wind.

### `presentation` (custom scene mode)

`presentation` is optional. When present, it rewrites the generated scene's visible stage instead of leaving the template cast on screen:

```json
"presentation": {
  "background": "acb_0000n",
  "music": "bgm04",
  "hideUnlisted": true,
  "speakerFocus": true,
  "speakerGroups": {
    "$narration": ["クロス", "ウインド"],
    "ポロン": ["クロス", "ウインド"],
    "クロス": ["クロス", "ウインド"],
    "ウインド": ["クロス", "ウインド"],
    "モモ": ["モモ"]
  },
  "characters": [
    { "id": "ポロン", "file": "ch01_cl01_p01.psb", "show": false, "x": 0, "y": 0, "z": 0, "order": 0, "scale": 100 },
    { "id": "モモ", "file": "ch02_cl01_p01.psb", "show": true, "x": 0, "y": 0, "z": 0, "order": 1, "scale": 100 },
    { "id": "クロス", "file": "ch03_cl01_p01.psb", "show": true, "x": -420, "y": 0, "z": 0, "order": 1, "scale": 100 },
    { "id": "ウインド", "file": "ch18_cl03_p01.psb", "show": true, "x": 420, "y": 0, "z": 0, "order": 2, "scale": 100 }
  ]
}
```

- `background` is an installed background key such as `acb_0000n`.
- `music` is an installed BGM key such as `bgm04`. Omit it to retain the template label's music.
- `hideUnlisted: true` hides native character objects not listed here; `false` leaves them alone.
- `speakerFocus: true` removes inherited CG, camera, effect, and character-timeline commands from the generated scene. Without groups it shows the configured speaker on voiced pages and uses each character's `show` fallback for narration. Set it to `false` or omit it to retain the compatible template-timeline behavior.
- `speakerGroups` optionally maps each speaker key to the configured characters that should remain visible on that speaker's pages. `$narration` controls unnamed narration. For example, Pollon can speak while Cross and Wind remain on screen and Pollon's sprite stays hidden.
- Each character `id` is the exact engine character key used by the message name box. `file` is an installed character PSB. `x`, `y`, `z`, `order`, and `scale` emit explicit native layout actions; unlike a position-name hint, these coordinates reliably separate multiple sprites. `show` supplies the fallback narration visibility when no `$narration` group exists.
- Existing objects are updated in place; an unlisted character is added to the first presentation data block. That lets a custom scene choose its cast without distributing copyrighted sprite assets.

The engine still needs a native message-window/checkpoint shell for text, input, saves, and archive metadata. With `speakerFocus`, CG, effects, camera, and character commands from that shell are discarded. Without `presentation`, native mode keeps the template choreography; blank mode still generates the message timeline but can retain other shell state.

### `pages`

Each object has:

- `speaker`:  engine key, or an empty string for narration. Empty speakers
  default to the engine's grid narration window; named
  speakers default to the regular dialogue window.
- `window`: optional explicit override, either `"narration"` or `"dialogue"`.
  Use `"narration"` with a non-empty speaker for a side/background character
  speaking through the grid window while retaining their displayed name. The prologue does this type of dialogue. 

Both window styles still use the native dialogue-page command (`text 1`). The
engine's `text 0` form is a control startline, not the narration style switch.
The build emits the retail game's `msgwin` transition tag and also
records the selected window type in the page state.
- `text`: message body. JSON `\n` creates an explicit line break.
- `voiceId` (optional): an exact installed voice-block ID. Use this when the
  default pool selection is too short, a grunt/reaction, or otherwise wrong for
  the page. The build searches the decompiled scenario tree and stops if
  the requested ID is missing or belongs to another speaker.

For explanatory lines, choose a full-sentence cue with a duration close to the
page's reading time. Avoid IDs whose catalog text is only a reaction (`Ah?!`,
`Huh?`, `...`, etc.) unless the page is intentionally a reaction. The shipped
guide maps its long pages explicitly; the IDs and source text can be reviewed in
the generated scenario JSON after a build.

In native mode, the number of pages must exactly equal the template label's `texts.Count`. In blank mode, the build creates the required text/checkpoint entries for every page, so any positive page count is supported. Keep text close to normal game message length; long pages can overflow or become uncomfortable even when the build succeeds.

The Game scene browser can view any native label or fork it into the project. A fork uses that storage/label as its template, copies the original pages into editable `pages`, creates an edge back to the original next target, and stores a read-only `forkSource.originalScene` snapshot for reference.

### `next`

`next` is the outgoing edge after the generated scene:

```json
"next": { "storage": "ac_05_01.ks", "target": "*start" }
```

Use `null` for an isolated launcher stub that ends after its template finishes. For an inserted scene, point `next` back to the displaced story edge or to a generated continuation target.

Generated-scene `next` edges can chain any number of custom scenes. A final `next` edge is also how a branch returns to the original story.

## Finding native labels, lines, and edges

List every label in a scenario:

```powershell
& .\tools\Inspect-Scenario.ps1 `
  -ScenarioJson '..\base-scenario-json\ac_07_03.ks.scn.m.json'
```

Show every dialogue page and the outgoing edge for one label:

```powershell
& .\tools\Inspect-Scenario.ps1 `
  -ScenarioJson '..\base-scenario-json\ac_07_03.ks.scn.m.json' `
  -Label '*check_BMI2'
```

Search for a line fragment, optionally restricted to a speaker:

```powershell
& .\tools\Inspect-Scenario.ps1 `
  -ScenarioJson '..\base-scenario-json\ac_07_03.ks.scn.m.json' `
  -SearchText 'Look at this' `
  -Speaker 'クロス'
```

Copy the final full text exactly from the tool output into an `afterLine` match. Matching is case-sensitive and punctuation-sensitive during the build.

List all observed speaker keys across the game:

```powershell
& .\tools\List-Speakers.ps1 `
  -ScenarioJsonRoot '..\base-scenario-json' `
  -MinimumLines 5
```

## Cataloging and previewing voice blocks

A dialogue page stores its voice cue in the third element of the native `texts` entry. The cue object has the exact archive ID (`voice`), Japanese speaker key (`name`), Japanese timing (`time`), English timing (`time_en` when present), and the waveform envelope used by the message window. Stand-alone `playvoice` commands are also indexed by the extractor.

The retail voice archive is packed, so unpack it once with the same FreeMote key used by the CoZ tools. The `-k` option belongs after the `info-psb` command:

```powershell
Push-Location '..\voice-archive-input'
& '..\external-tools\FreeMote\PsbDecompile.exe' info-psb -k 5fWhAHt4zVn2X 'voice_info.psb.m'
Pop-Location
```

Build a searchable catalog of every ID referenced by the decompiled scenarios:

```powershell
& .\tools\Extract-VoiceBlocks.ps1 `
  -ScenarioJsonRoot '..\base-scenario-json' `
  -OutputRoot '..\voice-export'
```

If `-VoiceRoot` points at the unpacked `voice` directory, `-IncludeArchiveInventory` adds archive-only cues as well. This produces the complete archive inventory (including cues not referenced by the scenarios you decompiled):

```powershell
& .\tools\Extract-VoiceBlocks.ps1 `
  -ScenarioJsonRoot '..\base-scenario-json' `
  -VoiceRoot '..\voice-archive-input\voice' `
  -IncludeArchiveInventory `
  -OutputRoot '..\voice-export'
```

For an ID-only archive catalog, `-ScenarioJsonRoot` can be omitted:

```powershell
& .\tools\Extract-VoiceBlocks.ps1 `
  -VoiceRoot '..\voice-archive-input\voice' `
  -IncludeArchiveInventory `
  -OutputRoot '..\voice-id-list'
```

Extract only the IDs you want to audition. FreeMote writes the native XWMA container under `audio`; the tool also copies it to `playable\\<id>.wma` so VLC or Windows Media Player can recognize it:

```powershell
& .\tools\Extract-VoiceBlocks.ps1 `
  -ScenarioJsonRoot '..\base-scenario-json' `
  -VoiceRoot '..\voice-archive-input\voice' `
  -PsbDecompilePath '..\external-tools\FreeMote\PsbDecompile.exe' `
  -Ids 'ac_03_20_win0000','ac_03_20_pol0000' `
  -ExtractAudio `
  -OutputRoot '..\voice-selection'
```

The extractor refuses a large accidental extraction by default (`-MaxExtract 100`). Use `-IdFile ids.txt` for a curated list, or raise the limit deliberately. `-Open` launches the first selected `.wma` after extraction. The script reads the local archive and never puts original voice assets in the patch package.

If native `.wma` playback stutters in VLC, add `-ConvertWav` (and optionally `-VlcPath`) to create clean PCM WAV copies under `wav\\`. Use those WAV files for auditioning; this does not alter the archive or the game patch.

## Entry method 1: launcher-only startup scene

Set `launchAlias.sourceScene` to the generated scene id and leave `injections` empty. Build and install normally, then run the launcher and choose GAME START.

The normal index keeps ordinary story routing, so this is the safest way to test a scene. The shipped tutorial uses it.

## Entry method 2: branch at the end of a specific label

Use an `edge` injection when the custom scene should begin after all instructions and dialogue in an existing label have finished.

```json
{
  "kind": "edge",
  "id": "before_true_ending_finalization",
  "source": {
    "storage": "ac_11_08.ks",
    "target": "*dummy2"
  },
  "expectedNext": {
    "storage": "ac_11_08.ks",
    "target": "*dummy3"
  },
  "destination": {
    "storage": "ac_ex_example.ks",
    "target": "*start"
  }
}
```

The fields mean:

- `source`: exact existing storage and label whose outgoing edge is patched.
- `expectedNext`: exact original edge that must exist once. This is a compatibility assertion.
- `destination`: custom edge replacing that one original edge.

If the source has multiple outgoing edges, only the edge matching `expectedNext` is replaced; all others remain. This allows branch-specific injection when an existing native label already has conditional routing. The declarative format does not currently author new condition expressions or choice menus.

To return after the inserted scene, set that generated scene's `next` to the displaced `expectedNext` value. The full example is in `examples/edge-injection.json`.

## Entry method 3: branch after one specific spoken line

Use `afterLine` when the insertion belongs inside an existing native label rather than after it.

```json
{
  "kind": "afterLine",
  "id": "after_cross_says_look",
  "source": {
    "storage": "ac_07_03.ks",
    "target": "*check_BMI2"
  },
  "line": {
    "speaker": "クロス",
    "text": "Look at this."
  },
  "expectedNext": {
    "storage": "ac_07_03.ks",
    "target": "*check_cross"
  },
  "destination": {
    "storage": "ac_ex_example.ks",
    "target": "*start"
  },
  "resumeTarget": "*fan_resume_after_look"
}
```

For an `afterLine` injection, the build:

1. Loads the CoZ override of `source.storage` when present, otherwise the retail decompile.
2. Resolves exactly one `source.target` label.
3. Verifies exactly one `expectedNext` edge.
4. Resolves exactly one dialogue entry with the exact `line.text` and optional exact `line.speaker`.
5. Finds the native display instruction for that dialogue entry.
6. Ends the original label immediately after the display instruction and routes it to `destination`.
7. Creates a new label named `resumeTarget` from the remaining native instructions.
8. Re-bases the continuation's checkpoint numbers and preserves its original outgoing edges.
9. Adds the continuation to both the scene-registry list and lookup map.

The inserted generated scene must have:

```json
"next": {
  "storage": "ac_07_03.ks",
  "target": "*fan_resume_after_look"
}
```

The build validates that return edge. It refuses a destination that is not a generated scene in the same project or does not return to the declared continuation.

### Line-injection cautions

- Match one full line exactly. Duplicate matches fail; add the speaker when needed.
- `resumeTarget` must start with `*`, must be unique inside the source storage, and should use a `*fan_resume_` prefix.
- The source label must have dialogue, native display instructions, at least one later checkpoint, and an outgoing edge.
- Avoid first experiments inside save/load, choice, phone, or highly interactive labels.
- The continuation preserves native state from the next checkpoint, but visual choreography still comes from the retail label and must be tested in game.
- If the insertion should occur after the last line of a label, use `edge`; it is simpler to use.


## Selecting a useful presentation template

For native mode, choose a candidate label using these criteria:

1. Its dialogue-page count is close to the scene you want to write.
2. Its original characters match the people who should be visible.
3. Its background, music, and transitions fit the intended location and tone.
4. It is linear dialogue rather than a save/load, selection, phone, or minigame sequence.
5. Its template storage contains voice cues for every key placed in `voiceCharacters`.

Inspect the label's pages and edges first. Build a launcher-only experiment, test the complete timeline, then add a normal-story injection.

For blank mode, the label is a shell rather than a pacing template. It must contain at least one ordinary dialogue/checkpoint entry, but its page count is ignored. Do not pad pages with empty text; empty bodies are rejected and blank dialogue creates poor save/backlog behavior.

## Chaining and branching patterns

### Linear custom sequence

Set Scene A's `next` to Scene B `*start`, then Scene B's `next` to the original story destination. Every generated scene is registered automatically.

### Temporary story detour

Use an edge injection into Scene A. Point the last custom scene back to `expectedNext`.

### Mid-label detour

Use an after-line injection into Scene A. Point the last custom scene back to `source.storage + resumeTarget`.

### Permanent alternate route

Point the final custom scene somewhere other than the displaced route. This deliberately changes continuity and may skip flags or post-evaluations. Only do this after inspecting downstream state dependencies.

### Conditional branch

The build can replace one existing conditional edge by matching its storage and target. Schema version 2 cannot create a new condition, choice menu, or flag expression; that would require a lower-level command/evaluation layer.

## What the build checks

The build stops on:

- unsupported schema versions;
- duplicate scene ids;
- missing template JSON or resources;
- template/page-count mismatch;
- missing character voice pools;
- empty dialogue bodies;
- missing or ambiguous injection labels;
- missing or ambiguous expected edges;
- missing or duplicate line matches;
- missing native display instructions;
- invalid or colliding continuation labels;
- an after-line destination that does not return correctly;
- generated scene or registry collisions;
- compiler/decompiler failures;
- missing final indexes or body.

Before a release, decompile the final archives, verify every inserted edge and registry entry, rebuild the xdelta payloads, test install/uninstall and interrupted-launch recovery, and hash the live installation.


## A Thank You

I thank you for trying out my tool. It has been a lot of hardwork (espicially writing this documentation). If you have any questions feel free to open up an issue on the github page even if it is just a general question. I hope I made the tool simple enough to use. Please use the GUI editor for ease of use as it handles a lot of things.
