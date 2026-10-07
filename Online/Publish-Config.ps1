$ErrorActionPreference = 'Stop'
try {
    $configPath = Join-Path $PSScriptRoot 'configuration.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.schemaVersion -ne 1 -or $config.revision -lt 1) { throw 'Invalid schemaVersion/revision.' }
    $rclone = 'C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $rclone = (Get-Command rclone -ErrorAction Stop).Source }
    $remotePath = Join-Path ([IO.Path]::GetTempPath()) ('apple-store-config-' + [guid]::NewGuid().ToString() + '.json')
    try {
        $ErrorActionPreference = 'Continue'
        & $rclone copyto 'r2:appleipa-files/apple-store/configuration.json' $remotePath --ignore-times 2>&1 | Out-Null
        $readCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $remoteText = if ($readCode -eq 0) { Get-Content -LiteralPath $remotePath -Raw -Encoding UTF8 } else { '' }
    } finally { Remove-Item -LiteralPath $remotePath -Force -ErrorAction SilentlyContinue }
    if ($readCode -eq 0) {
        $current = ($remoteText -join "`n") | ConvertFrom-Json
        if ([int]$config.revision -lt [int]$current.revision) { throw 'Remote configuration is newer. Run Get-Config.cmd first.' }
        if ([int]$config.revision -eq [int]$current.revision -and ($config | ConvertTo-Json -Depth 30 -Compress) -ne ($current | ConvertTo-Json -Depth 30 -Compress)) { throw 'Increase revision by 1 before publishing changes.' }
    } elseif ($readCode -ne 3 -and $readCode -ne 4) { throw 'Cannot check current R2 configuration. Check connection and rclone access.' }
    & $rclone copyto $configPath 'r2:appleipa-files/apple-store/configuration.json' --s3-no-check-bucket --ignore-times --header-upload 'Cache-Control: no-cache' --progress
    if ($LASTEXITCODE -ne 0) { throw 'Upload failed. Existing local configuration was not changed.' }
    Write-Host 'Done. Configuration published. Open Settings and refresh in Apple Store 4.0.' -ForegroundColor Green
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
