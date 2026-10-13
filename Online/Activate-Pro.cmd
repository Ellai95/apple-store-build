@echo off
echo Apple Store Pro manager starting...
set "HTTPS_PROXY="
set "HTTP_PROXY="
set "ALL_PROXY="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Admin-Pro.ps1" -Mode Grant -Days 365
pause
