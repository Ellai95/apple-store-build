$ErrorActionPreference = 'Stop'
try {
    $rclone = 'C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $rclone = (Get-Command rclone -ErrorAction Stop).Source }
    $path = Join-Path $PSScriptRoot 'configuration.json'
    $temp = Join-Path $PSScriptRoot 'configuration.download.json'
    & $rclone copyto 'r2:appleipa-files/apple-store/configuration.json' $temp --ignore-times --progress
    if ($LASTEXITCODE -ne 0) { throw 'Download failed. Your local file was not changed.' }
    $value = Get-Content -LiteralPath $temp -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($value.schemaVersion -ne 1) { throw 'Unexpected configuration format.' }
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination "$path.bak" -Force }
    Move-Item -LiteralPath $temp -Destination $path -Force
    Write-Host 'Current configuration downloaded.' -ForegroundColor Green
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
