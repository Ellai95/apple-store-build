param([string]$IpaPath, [string]$ReleasePath, [string]$ProfilePath)
$ErrorActionPreference = 'Stop'
try {
    if (!$IpaPath) { $IpaPath = (Read-Host 'Drop or paste the path to Apple Store.ipa').Trim('"') }
    if (!$ReleasePath) { $ReleasePath = Join-Path (Split-Path -Parent $IpaPath) 'release.json' }
    if (!(Test-Path -LiteralPath $IpaPath -PathType Leaf)) { throw 'IPA file does not exist.' }
    $release = Get-Content -LiteralPath $ReleasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($release.bundleID -ne 'ru.ipa95.applestore' -or $release.version -notmatch '^\d+(\.\d+){0,2}$' -or [int]$release.build -lt 400) { throw 'Wrong release.json.' }
    if ((Get-FileHash -LiteralPath $IpaPath -Algorithm SHA256).Hash.ToLower() -ne $release.sha256.ToLower()) { throw 'IPA and release.json do not match. Use both original files from the same GitHub artifact.' }
    if ((Get-Item -LiteralPath $IpaPath).Length -ne $release.sizeBytes) { throw 'IPA size mismatch.' }
    $profile = $null
    if ($ProfilePath) {
        $profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($profile.version -ne $release.version -or [int]$profile.build -ne [int]$release.build) { throw 'This test publisher requires version 4.2, build 420, from this package.' }
        if ($profile.announcement.action -ne 'update' -or !$profile.announcement.modal -or [int]$profile.announcement.maxBuild -ne ([int]$release.build - 1)) { throw 'Invalid announcement targeting.' }
    }
    $configPath = Join-Path $PSScriptRoot 'configuration.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$profile -and $config.update.enabled -and [int]$release.build -le [int]$config.update.build) { throw 'This release or a newer one is already in configuration.json.' }
    $rclone = 'C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $rclone = (Get-Command rclone -ErrorAction Stop).Source }
    . (Join-Path $PSScriptRoot 'Read-RemoteConfig.ps1')
    $current = Get-StoreRemoteConfiguration -Rclone $rclone
    if ($null -ne $current) {
        if (!$profile -and [int]$current.revision -gt [int]$config.revision) { throw 'Remote configuration is newer. Run Get-Config.cmd and reapply release notes.' }
        if ($current.update.enabled -and [int]$current.update.build -ge [int]$release.build) { throw 'This release or a newer one is already published.' }
        if ($profile) { $config = $current } # Preserve the current online tariffs, texts and appearance.
    }
    if ($config.schemaVersion -ne 1 -or [int]$config.revision -lt 1) { throw 'Invalid configuration.' }
    if ($profile) {
        $config.update.notes = @($profile.notes)
        $config.news = @($profile.announcement) + @($config.news | Where-Object { $_.id -ne $profile.announcement.id })
        $config.changelog = @($profile.changelog) + @($config.changelog | Where-Object { $_.id -ne $profile.changelog.id })
        if ($config.news.Count -gt 20 -or $config.changelog.Count -gt 100) { throw 'Too many news or changelog items. Remove older items first.' }
        $config.features.selfUpdate = $true
        if (@($config.layout.home) -notcontains 'news') { $config.layout.home = @($config.layout.home) + @('news') }
        if (@($config.layout.settings) -notcontains 'update') { $config.layout.settings = @($config.layout.settings) + @('update') }
    }
    $name = "Apple-Store-$($release.version)-$($release.build).ipa"
    $key = "apple-store/releases/$name"
    # Immutable versioned key: publishing new metadata never redirects an active download to another IPA.
    & $rclone copyto $IpaPath "r2:appleipa-files/$key" --s3-no-check-bucket --immutable --progress
    if ($LASTEXITCODE -ne 0) { throw 'IPA upload failed. Configuration was not published.' }
    $config.update.enabled = $true
    foreach ($field in @('version','build','sha256','bundleID','sizeBytes','minimumIOS')) { $config.update.$field = $release.$field }
    $config.update.ipaURL = "https://pub-d11175355ab34b9299fb0a916702bce7.r2.dev/$key"
    $config.revision = [int]$config.revision + 1
    Copy-Item -LiteralPath $configPath -Destination "$configPath.bak" -Force
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
    & (Join-Path $PSScriptRoot 'Publish-Config.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Configuration upload failed; retry Publish-Config.cmd.' }
    Write-Host 'Done. Update published. Devices need Apple Store 4.0 or newer to see this screen.' -ForegroundColor Green
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
