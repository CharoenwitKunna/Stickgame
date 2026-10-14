@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_godot.ps1" -Mode play
if errorlevel 1 pause
