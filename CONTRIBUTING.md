# Contributing

Keep changes small enough to review and run the local checks before opening a pull request.

## Automated checks

The test suite does not require game files or FreeMote:

```powershell
python -m compileall -q SOURCE/Editor SOURCE/tests
python SOURCE/Editor/ac_script_editor.py --validate SOURCE/project.json
python -m SOURCE.Editor.ac_script_editor --validate SOURCE/project.json
python -m unittest discover -s SOURCE/tests -p "test_*.py" -v
pwsh -NoProfile -File SOURCE/tests/Test-ScenarioBuild.ps1
```

CI runs the same commands on Windows for every push and pull request.

## Game-data integration check

Changes to scenario compilation or archive packaging also need a local integration build. Supply an English Steam installation with the Committee of Zero patch, a decompiled scenario root, and FreeMote as described in `SOURCE/DEVELOPER-GUIDE.md`. Do not commit extracted game data, compiled archives, or proprietary game assets.

After building, decompile the resulting scenario files and compare the affected labels, edges, dialogue counts, and checkpoints with the intended project definition. Test both the temporary GAME START overlay and permanent install/uninstall paths before publishing a release.

## Source boundaries

- `SOURCE/Build/ScenarioBuild.psm1` contains deterministic build primitives that can be tested without game files.
- `SOURCE/build.ps1` performs the asset-dependent compilation and archive assembly.
- `SOURCE/Editor/project_model.py` owns project defaults and validation rules.
- `SOURCE/tests` contains dependency-free regression tests.

When a defect can be reproduced without proprietary data, add a regression test with the fix.
