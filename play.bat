@echo off
cd /d "%~dp0"
set "GODOT=C:\Users\User\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64.exe"
if exist "%GODOT%" (
    start "" "%GODOT%" --path "%~dp0"
) else (
    powershell -ExecutionPolicy Bypass -File .\run_godot.ps1 play
)
