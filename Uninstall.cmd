@echo off
setlocal
set "GAME_PATH=%~1"
if "%GAME_PATH%"=="" set /p "GAME_PATH=Enter your ANONYMOUS;CODE install folder: "
if "%GAME_PATH%"=="" exit /b 2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" -GamePath "%GAME_PATH%"
echo.
pause
