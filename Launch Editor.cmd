@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "SOURCE\Editor\ac_script_editor.py" "%~dp0SOURCE\project.json"
) else (
  python "SOURCE\Editor\ac_script_editor.py" "%~dp0SOURCE\project.json"
)
if errorlevel 1 pause
