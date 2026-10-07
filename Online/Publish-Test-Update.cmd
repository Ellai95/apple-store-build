@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-Release.ps1" -ProfilePath "%~dp0test-release-4.1.json"
pause
