@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Admin-Ads.ps1" -Mode Revoke
pause
