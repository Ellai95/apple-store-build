@echo off
echo Reading current Pro settings...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Admin-Pro.ps1" -Mode Get
pause
