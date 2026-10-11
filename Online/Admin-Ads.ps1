param([ValidateSet('Publish','Grant','Revoke','Stop')][string]$Mode='Publish', [string]$Code='', [int]$Days=0)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
$work=Join-Path $PSScriptRoot 'ads-work'
$remote='r2:appleipa-files/apple-store/configuration.json'
$marker='__STORE_ADS_DATE_70b34__'
function ReadJson([string]$path) {
    $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    if ($text.Contains($script:marker)) { throw 'Reserved marker found.' }
    $text=[regex]::Replace($text,'"(?=\d{4}-\d{2}-\d{2}T)',('"'+$script:marker))
    return ($text | ConvertFrom-Json)
}
function WriteJson([string]$path,$object) {
    $text=($object | ConvertTo-Json -Depth 100).Replace($script:marker,'')
    if ([Text.Encoding]::UTF8.GetByteCount($text) -gt 524288) { throw 'Configuration exceeds the app limit. Nothing published.' }
    [IO.File]::WriteAllText($path,$text,$script:utf8)
}
function CopyStore([string]$from,[string]$to) {
    & $script:rclone copyto $from $to --s3-no-check-bucket --contimeout 20s --timeout 2m --retries 3 --header-upload 'Cache-Control: no-cache'
    if ($LASTEXITCODE -ne 0) { throw 'R2 request failed. Keep Happ connected if using proxy.' }
}
function SecureURL([string]$text) {
    $uri=$null
    return [Uri]::TryCreate($text,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https' -and !$uri.UserInfo -and $uri.Host -and $uri.Host -notin @('localhost','127.0.0.1','::1')
}
function ValidDate([string]$text) {
    $date=[DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse($text.Replace($script:marker,''),[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$date)
}
function ValidateAds($ads) {
    foreach($key in @('enabled','campaigns','purchaseEnabled','offers','paymentDetails','recipient','grants')) {
        if ($null -eq $ads.PSObject.Properties[$key]) { throw ('Missing advertising field: '+$key) }
    }
    if ($ads.enabled -isnot [bool] -or $ads.purchaseEnabled -isnot [bool] -or @($ads.campaigns).Count -gt 30 -or @($ads.offers).Count -gt 10 -or @($ads.grants).Count -gt 1000 -or $ads.paymentDetails.Length -gt 3000 -or $ads.recipient -notmatch '^https://t\.me/[a-zA-Z][a-zA-Z0-9_]{3,31}/?$') { throw 'Invalid advertising settings.' }
    $ids=@{}
    foreach($c in $ads.campaigns) {
        foreach($key in @('id','enabled','title','text','imageURL','icon','buttons','mode','intervalSeconds','priority','minBuild','maxBuild','startsAt','endsAt')) { if ($null -eq $c.PSObject.Properties[$key]) { throw ('Missing campaign field: '+$key) } }
        if (!$c.id -or $c.id.Length -gt 80 -or $ids.ContainsKey($c.id) -or $c.enabled -isnot [bool] -or $c.title.Length -gt 200 -or $c.text.Length -gt 5000 -or $c.icon.Length -gt 16 -or $c.mode -notin @('entry','interval','once') -or $c.intervalSeconds -lt 300 -or $c.intervalSeconds -gt 86400 -or $c.priority -lt -100 -or $c.priority -gt 100 -or $c.minBuild -lt 460 -or ($null -ne $c.maxBuild -and $c.maxBuild -lt $c.minBuild) -or @($c.buttons).Count -gt 4) { throw 'Invalid campaign. Nothing published.' }
        $ids[$c.id]=$true
        if ($null -ne $c.imageURL -and !(SecureURL $c.imageURL)) { throw 'Image must have a public HTTPS URL.' }
        foreach($date in @($c.startsAt,$c.endsAt)) { if ($null -ne $date -and !(ValidDate $date)) { throw 'Invalid campaign date.' } }
        $buttons=@{}
        foreach($b in $c.buttons) {
            if (!$b.id -or $b.id.Length -gt 80 -or $buttons.ContainsKey($b.id) -or !$b.title -or $b.title.Length -gt 100 -or !(SecureURL $b.url)) { throw 'Invalid advertisement button.' }
            $buttons[$b.id]=$true
        }
    }
    $ids=@{}
    foreach($o in $ads.offers) {
        if (!$o.id -or $o.id.Length -gt 50 -or $ids.ContainsKey($o.id) -or !$o.title -or $o.title.Length -gt 100 -or $o.enabled -isnot [bool] -or $o.days -lt 1 -or $o.days -gt 366 -or $o.price -lt 0 -or $o.price -gt 10000000 -or ($o.enabled -and $o.price -le 0)) { throw 'Invalid ad-free offer.' }
        $ids[$o.id]=$true
    }
    $ids=@{}
    foreach($g in $ads.grants) {
        if ($g.code -notmatch '^[A-Fa-f0-9]{32}$' -or $ids.ContainsKey($g.code.ToUpperInvariant()) -or !(ValidDate $g.expiresAt)) { throw 'Invalid personal access entry.' }
        $ids[$g.code.ToUpperInvariant()]=$true
    }
    if ($ads.purchaseEnabled -and ([string]::IsNullOrWhiteSpace($ads.paymentDetails) -or @($ads.offers | Where-Object {$_.enabled}).Count -eq 0)) { throw 'Specify prices and payment details before enabling purchases.' }
}
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $script:rclone='C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $script:rclone=(Get-Command rclone -CommandType Application -ErrorAction Stop).Source }
    $before=Join-Path $work 'configuration-before.json'
    CopyStore $remote $before
    $hash=(Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash
    $config=ReadJson $before
    if ($config.schemaVersion -ne 1 -or $config.revision -lt 1) { throw 'Invalid current configuration.' }
    $oldAds=$config.advertisements
    if ($Mode -eq 'Publish') {
        $ads=ReadJson (Join-Path $PSScriptRoot 'Advertising.json')
        # Personal permissions are edited only by Grant/Revoke, never by a campaign upload.
        $ads.grants=@()
        if ($null -ne $oldAds) { $ads.grants=@($oldAds.grants | Where-Object { $null -ne $_ }) }
    } else {
        if ($null -eq $oldAds) { throw 'Run Publish-Ads.cmd first, with advertising disabled.' }
        $ads=$oldAds
        if ($Mode -eq 'Stop') { $ads.enabled=$false }
        else {
            if (!$Code) { $Code=Read-Host 'Client code (32 characters)' }
            $Code=($Code -replace '[\s-]','').ToUpperInvariant()
            if ($Code -notmatch '^[A-F0-9]{32}$') { throw 'Paste the complete code shown in the app.' }
            $rows=@($ads.grants | Where-Object {$null -ne $_ -and $_.code.ToUpperInvariant() -ne $Code})
            if ($Mode -eq 'Grant') {
                if ($Days -eq 0) { $Days=[int](Read-Host 'Number of days: 30 or 365') }
                if ($Days -lt 1 -or $Days -gt 366) { throw 'Days must be between 1 and 366.' }
                $until=[datetime]::UtcNow.AddDays($Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
                $rows+= [PSCustomObject]@{code=$Code;expiresAt=$until}
                Write-Host ('Access expires: '+$until)
            }
            $ads.grants=@($rows)
        }
    }
    ValidateAds $ads
    $config | Add-Member -NotePropertyName advertisements -NotePropertyValue $ads -Force
    $epoch=[datetime]::SpecifyKind([datetime]'1970-01-01',[DateTimeKind]::Utc)
    $config.revision=[Math]::Max([long]([datetime]::UtcNow-$epoch).TotalSeconds,[long]$config.revision+1)
    $next=Join-Path $work 'configuration-ads.json'; WriteJson $next $config
    $check=Join-Path $work 'configuration-preflight.json';CopyStore $remote $check
    if ((Get-FileHash -LiteralPath $check -Algorithm SHA256).Hash -ne $hash) { throw 'Configuration changed. Run again; nothing published.' }
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup=Join-Path $work ('configuration-backup-'+$stamp+'.json');Copy-Item -LiteralPath $before -Destination $backup
    CopyStore $backup ('r2:appleipa-files/apple-store/backups/advertising/'+[IO.Path]::GetFileName($backup))
    CopyStore $next $remote
    $readback=Join-Path $work 'configuration-verified.json'; CopyStore $remote $readback
    if ((Get-FileHash -LiteralPath $readback -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $next -Algorithm SHA256).Hash) { throw 'Read-back verification failed. Keep the backup and report the error.' }
    Write-Host 'DONE. Advertising settings updated. App checks changes while open or on refresh.' -ForegroundColor Green
} catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;Write-Host $_.ScriptStackTrace;exit 1 }
