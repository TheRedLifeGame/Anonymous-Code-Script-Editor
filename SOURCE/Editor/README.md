# A;C Script Studio

Start the editor by double-clicking `Launch Editor.cmd` in the project root.

The editor reads and writes schema-v2 scene project JSON.

FreeMote is not included in the published editor. Set `AC_TOOL_ROOT` to a folder containing `FreeMote\\PsbDecompile.exe` and `FreeMote\\PsBuild.exe`, or choose the extractor/build-tools folder when the editor prompts. The user supplies the game install; scenario JSON is generated into the local cache automatically.

Game `.mzv` files are MP4 containers and a zero-sized `ftyp` header that ordinary players reject. The editor repairs that header, writes an `.mp4` compatibility copy under `assets/extracted/videos/`, and prefers VLC for playback before falling back to Windows Media Player.

“View original scene” is a read-only inspector for the selected native label. It shows storage, label, page count, speakers, and extracted dialogue text; “Fork into project” creates the editable project copy.

The game stores most sound and PSB graphics in proprietary archives. After a game folder is selected, the editor creates a per-user cache of the c0patch scenario index and decompiled scenario JSON.

Validate a project from the command line with:

```powershell
python .\SOURCE\Editor\ac_script_editor.py --validate .\SOURCE\project.json
```

## Files

`ac_script_editor.py` is the command-line and GUI entry point. The remaining files contain the editor's supporting code:

- `project_model.py` contains project defaults, normalization, and validation.
- `asset_catalog.py` indexes native scenes, music, media, character keys, and sprites.
- `editor_views.py` builds the light-theme Tkinter shell and editing tabs.
- `editor_controller.py` contains scene, dialogue, branch, and native-scene editing behavior.
- `editor_assets.py` handles background indexing, previews, playback, and asset actions.
- `editor_navigation.py` contains native-scene filtering, dialogue search, and asset-to-scene shortcuts.
- `editor_preferences.py` stores recent projects and editor preferences outside the project file.

Selecting a game with `windata/c0patch_info.psb.m` and `windata/c0patch_body.bin` prepares the local scenario cache. The cache lives under `%LOCALAPPDATA%\\A-C Script Studio\\game-cache` and is regenerated when the installed archive changes. Set `AC_EXTRACT_ROOT` and `AC_SCENARIO_JSON_ROOT` to use existing extracted roots.

Development and test commands are listed in `CONTRIBUTING.md` at the repository root.
