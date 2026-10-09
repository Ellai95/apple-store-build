@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-Release.ps1" -ProfilePath "%~dp0release-4.4.json"
pause
