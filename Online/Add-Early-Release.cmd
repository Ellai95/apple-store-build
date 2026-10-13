@echo off
echo Early release uploader starting...
set "HTTPS_PROXY="
set "HTTP_PROXY="
set "ALL_PROXY="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Upload-Early.ps1"
pause
