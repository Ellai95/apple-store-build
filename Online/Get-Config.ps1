$ErrorActionPreference = 'Stop'
try {
    $rclone = 'C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $rclone = (Get-Command rclone -ErrorAction Stop).Source }
    . (Join-Path $PSScriptRoot 'Read-RemoteConfig.ps1')
    $value = Get-StoreRemoteConfiguration -Rclone $rclone
    if ($null -eq $value) { throw 'No online configuration exists yet. Your local file was not changed.' }
    $path = Join-Path $PSScriptRoot 'configuration.json'
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination "$path.bak" -Force }
    [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Current configuration downloaded.' -ForegroundColor Green
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
