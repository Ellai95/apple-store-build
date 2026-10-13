@echo off
echo Early release uploader starting...
set "HTTPS_PROXY=socks5://127.0.0.1:10808"
set "HTTP_PROXY=socks5://127.0.0.1:10808"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Upload-Early.ps1"
pause
