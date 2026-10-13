@echo off
echo Apple Store Pro manager starting...
set "HTTPS_PROXY=socks5://127.0.0.1:10808"
set "HTTP_PROXY=socks5://127.0.0.1:10808"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Admin-Pro.ps1" -Mode Disable -Days 365
pause
