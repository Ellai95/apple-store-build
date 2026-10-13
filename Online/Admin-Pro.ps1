param([ValidateSet('Publish','PublishServices','Grant','Revoke','Disable','Get','AddEarly')][string]$Mode='Publish', [string]$Code='', [int]$Days=365, [string[]]$Features=@('premiumThemes','customWallpaper','noAds'), [string]$EarlyJson='')
$ErrorActionPreference='Stop'
Write-Host 'Apple Store Pro manager' -ForegroundColor Cyan
if ($Mode -in @('Grant','Revoke')) {
    if (!$Code) { $Code=Read-Host 'Personal device code (32 characters)' }
    $Code=($Code -replace '[\s-]','').ToUpperInvariant()
    if ($Code -notmatch '^[A-F0-9]{32}$') { Write-Host 'Invalid device code.' -ForegroundColor Red; exit 1 }
}

$utf8=New-Object Text.UTF8Encoding($false)
$work=Join-Path $PSScriptRoot 'pro-work'
$remote='r2:appleipa-files/apple-store/configuration.json'
$marker='__STORE_PRO_DATE_84ab__'
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
    Write-Host 'R2 request: please wait (up to 45 seconds)...'
    & $script:rclone copyto $from $to --s3-no-check-bucket --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1 --header-upload 'Cache-Control: no-cache'
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
function ValidatePersonalization($doc) {
    if ($null -ne $doc.services) { ValidateServices $doc.services }
    foreach($key in @('enabled','themes','pro')) { if ($null -eq $doc.PSObject.Properties[$key]) { throw ('Missing field: '+$key) } }
    $pro=$doc.pro
    foreach($key in @('enabled','testing','purchaseEnabled','offers','paymentDetails','recipient','grants','features')) { if ($null -eq $pro.PSObject.Properties[$key]) { throw ('Missing Pro field: '+$key) } }
    if ($doc.enabled -isnot [bool] -or $pro.enabled -isnot [bool] -or $pro.testing -isnot [bool] -or $pro.purchaseEnabled -isnot [bool] -or @($doc.themes).Count -lt 1 -or @($doc.themes).Count -gt 30 -or @($pro.offers).Count -gt 10 -or @($pro.grants).Count -gt 1000 -or $pro.paymentDetails.Length -gt 3000 -or $pro.recipient -notmatch '^https://t\.me/[a-zA-Z][a-zA-Z0-9_]{3,31}/?$') { throw 'Invalid personalization document.' }
    if ($pro.testing) { throw 'Online preview unlock is forbidden. Set pro.testing=false; use a personal Grant for testing.' }
    $ids=@{}; $hasClassic=$false
    foreach($t in $doc.themes) {
        foreach($key in @('id','title','subtitle','requiresPro','style','dark','accent','secondary','lightBackground','darkBackground','lightSurface','darkSurface')) { if ($null -eq $t.PSObject.Properties[$key]) { throw ('Missing theme field: '+$key) } }
        if ($t.id -notmatch '^[a-z0-9-]{1,50}$' -or $ids.ContainsKey($t.id) -or !$t.title -or $t.title.Length -gt 80 -or $t.subtitle.Length -gt 200 -or $t.requiresPro -isnot [bool] -or $t.dark -isnot [bool] -or $t.style -notin @('solid','aurora','gold','ocean','custom')) { throw 'Invalid theme.' }
        $ids[$t.id]=$true
        foreach($key in @('accent','secondary','lightBackground','darkBackground','lightSurface','darkSurface')) { if ($t.$key -notmatch '^#[a-fA-F0-9]{6}$') { throw 'Use #RRGGBB theme colors.' } }
        if ($null -ne $t.imageURL -and !(SecureURL $t.imageURL)) { throw 'Use an HTTPS image URL.' }
        if ($t.id -eq 'classic' -and !$t.requiresPro -and $t.style -eq 'solid') { $hasClassic=$true }
    }
    if (!$hasClassic) { throw 'Keep the free classic theme.' }
    if ($null -ne $pro.payment) {
        if ($pro.payment.bank.Length -gt 100 -or [string]::IsNullOrWhiteSpace($pro.payment.bank) -or $pro.payment.holder.Length -gt 100 -or [string]::IsNullOrWhiteSpace($pro.payment.holder) -or $pro.payment.cardNumber -notmatch '^[0-9]{12,19}$' -or $pro.payment.phone -notmatch '^\+[0-9]{7,15}$') { throw 'Invalid payment details.' }
    }
    if ($null -ne $doc.extras) {
        foreach($flag in @('earlyAccess','parallelDownloads','glassTheme','featureRequests')) { if ($doc.extras.$flag -isnot [bool]) { throw 'Invalid Pro feature switch.' } }
        if (@($doc.extras.earlyReleases).Count -gt 20) { throw 'Too many early releases.' }
        if (@($doc.extras.deviceOverrides).Count -gt 1000) { throw 'Too many individual profiles.' }
        $overrides=@{}
        foreach($item in $doc.extras.deviceOverrides) {
            if ($item.code -notmatch '^[a-fA-F0-9]{32}$' -or $overrides.ContainsKey($item.code.ToUpperInvariant())) { throw 'Invalid personal feature override.' }
            if (@($item.flags.PSObject.Properties).Count -gt 30) { throw 'Too many profile switches.' }
            foreach($flag in $item.flags.PSObject.Properties) { if ($flag.Name -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,59}$' -or $flag.Value -isnot [bool]) { throw 'Unknown personal feature switch.' } }
            $overrides[$item.code.ToUpperInvariant()]=$true
        }
        $releaseIDs=@{}
        foreach($r in $doc.extras.earlyReleases) {
            if (!$r.id -or $r.id.Length -gt 60 -or $releaseIDs.ContainsKey($r.id) -or !$r.name -or $r.name.Length -gt 150 -or $r.catalogID.Length -gt 100 -or $r.version.Length -gt 50 -or $r.notes.Length -gt 3000 -or $r.sizeBytes -le 0 -or !(SecureURL $r.ipaURL) -or @($r.allowedCodes).Count -gt 1000) { throw 'Invalid early release.' }
            foreach($code in $r.allowedCodes) { if ($code -notmatch '^[a-fA-F0-9]{32}$') { throw 'Invalid early-release audience.' } }
            if ($null -ne $r.expiresAt -and !(ValidDate $r.expiresAt)) { throw 'Invalid early-release expiry.' }
            $releaseIDs[$r.id]=$true
        }
    }

    $allowed=@('premiumThemes','customWallpaper','noAds')
    foreach($property in $pro.features.PSObject.Properties) { if ($property.Name -notin $allowed -or $property.Value -isnot [bool]) { throw 'Unknown Pro feature.' } }
    $ids=@{}
    foreach($offer in $pro.offers) {
        if (!$offer.id -or $offer.id.Length -gt 50 -or $ids.ContainsKey($offer.id) -or !$offer.title -or $offer.title.Length -gt 100 -or $offer.enabled -isnot [bool] -or $offer.days -lt 1 -or $offer.days -gt 366 -or $offer.price -lt 0 -or $offer.price -gt 10000000 -or ($offer.enabled -and $offer.price -le 0)) { throw 'Invalid Pro offer.' }; $ids[$offer.id]=$true
    }
    $ids=@{}
    foreach($g in $pro.grants) {
        if ($g.code -notmatch '^[A-Fa-f0-9]{32}$' -or $ids.ContainsKey($g.code.ToUpperInvariant()) -or !(ValidDate $g.expiresAt) -or $g.activationHash -notmatch '^[a-fA-F0-9]{64}$' -or @($g.features).Count -eq 0 -or @($g.features | Select-Object -Unique).Count -ne @($g.features).Count) { throw 'Invalid Pro grant.' }
        foreach($f in $g.features) { if ($f -notin $allowed) { throw 'Unknown Pro grant feature.' } }; $ids[$g.code.ToUpperInvariant()]=$true
    }
    if ($pro.purchaseEnabled -and (!$pro.enabled -or [string]::IsNullOrWhiteSpace($pro.paymentDetails) -or @($pro.offers | Where-Object {$_.enabled}).Count -eq 0)) { throw 'Specify prices and payment details before enabling purchases.' }
}

function ValidateServices($services) {
    if ($services.enabled -isnot [bool] -or [string]::IsNullOrWhiteSpace($services.title) -or $services.title.Length -gt 80 -or $services.subtitle.Length -gt 300 -or @($services.products).Count -gt 30) { throw 'Invalid services document.' }
    $ids=@{}
    foreach($product in $services.products) {
        if ($product.id -notmatch '^[a-z0-9-]{1,50}$' -or $ids.ContainsKey($product.id) -or $product.enabled -isnot [bool] -or [string]::IsNullOrWhiteSpace($product.title) -or $product.title.Length -gt 80 -or $product.subtitle.Length -gt 200 -or $product.description.Length -gt 3000 -or $product.monogram.Length -gt 8 -or $product.color -notmatch '^#[A-Fa-f0-9]{6}$' -or $product.category -notin @('Игры','Нейросети','Монтаж') -or $product.symbol -notin @('gamecontroller.fill','sparkles','brain.head.profile','scissors','desktopcomputer','play.rectangle.fill') -or @($product.platforms).Count -gt 5 -or @($product.plans).Count -lt 1 -or @($product.plans).Count -gt 15) { throw 'Invalid service product.' }
        $ids[$product.id]=$true
        foreach($platform in $product.platforms) { if ([string]::IsNullOrWhiteSpace($platform) -or $platform.Length -gt 30) { throw 'Invalid platform.' } }
        $plans=@{}
        foreach($plan in $product.plans) {
            if ($plan.id -notmatch '^[a-z0-9-]{1,50}$' -or $plans.ContainsKey($plan.id) -or $plan.enabled -isnot [bool] -or [string]::IsNullOrWhiteSpace($plan.title) -or $plan.title.Length -gt 80 -or $plan.period.Length -gt 80 -or $plan.detail.Length -gt 500) { throw 'Invalid service plan.' }
            $plans[$plan.id]=$true
            if ($null -ne $plan.price -and (($plan.price -isnot [int] -and $plan.price -isnot [long]) -or $plan.price -lt 1 -or $plan.price -gt 10000000)) { throw 'Invalid service price.' }
            if ($null -ne $plan.previousPrice -and ($null -eq $plan.price -or ($plan.previousPrice -isnot [int] -and $plan.previousPrice -isnot [long]) -or $plan.previousPrice -le $plan.price -or $plan.previousPrice -gt 10000000)) { throw 'Invalid previous service price.' }
        }
    }
}

try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $script:rclone='C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $script:rclone=(Get-Command rclone -CommandType Application -ErrorAction Stop).Source }
    $before=Join-Path $work 'configuration-before.json'
    Write-Host 'Step 1/4: reading current online configuration...'
    CopyStore $remote $before
    $hash=(Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash
    $config=ReadJson $before
    if ($config.schemaVersion -ne 1 -or $config.revision -lt 1) { throw 'Invalid current configuration.' }
    $oldDoc=$config.personalization
    if ($Mode -eq 'Get') {
        if ($null -eq $oldDoc) { throw 'No personalization has been published yet.' }
        $local=Join-Path $PSScriptRoot 'Personalization.json'
        if (Test-Path -LiteralPath $local) { Copy-Item -LiteralPath $local -Destination ($local+'.bak') -Force }
        WriteJson $local $oldDoc
        Write-Host 'DONE. Current themes/Pro settings downloaded.' -ForegroundColor Green
        exit 0
    }
    if ($Mode -eq 'PublishServices') {
        $template=ReadJson (Join-Path $PSScriptRoot 'Personalization.json')
        ValidateServices $template.services
        $doc=$oldDoc
        if ($null -eq $doc) { $doc=$template }
        $doc | Add-Member -NotePropertyName services -NotePropertyValue $template.services -Force
    } elseif ($Mode -eq 'Publish') {
        $doc=ReadJson (Join-Path $PSScriptRoot 'Personalization.json')
        $doc.pro.grants=@()
        if ($null -ne $oldDoc) { $doc.pro.grants=@($oldDoc.pro.grants | Where-Object {$null -ne $_}) }
    } else {
        $doc=$oldDoc
        if ($null -eq $doc) { $doc=ReadJson (Join-Path $PSScriptRoot 'Personalization.json') }
        if ($Mode -eq 'Disable') { $doc.pro.enabled=$false; $doc.pro.testing=$false }
        elseif ($Mode -eq 'AddEarly') {
            if (!(Test-Path -LiteralPath $EarlyJson -PathType Leaf)) { throw 'Early release metadata missing.' }
            $entry=ReadJson $EarlyJson
            if ($null -eq $doc.extras) {
                $template=ReadJson (Join-Path $PSScriptRoot 'Personalization.json')
                $doc | Add-Member -NotePropertyName extras -NotePropertyValue $template.extras -Force
            }
            $doc.extras.earlyReleases=@($doc.extras.earlyReleases | Where-Object {$null -ne $_ -and $_.id -ne $entry.id})+@($entry)
        }
        else {
            if (!$Code) { $Code=Read-Host 'Personal code (32 characters)' }
            $Code=($Code -replace '[\s-]','').ToUpperInvariant()
            if ($Code -notmatch '^[A-F0-9]{32}$') { throw 'Paste the complete code from the app.' }
            $rows=@($doc.pro.grants | Where-Object {$null -ne $_ -and $_.code.ToUpperInvariant() -ne $Code})
            if ($Mode -eq 'Grant') {
                if ($Days -eq 0) { $Days=[int](Read-Host 'Access duration: 30 or 365 days') }
                if ($Days -lt 1 -or $Days -gt 366) { throw 'Days must be between 1 and 366.' }
                foreach($f in $Features) { if ($f -notin @('premiumThemes','customWallpaper','noAds')) { throw 'Unknown feature.' } }
                $until=[datetime]::UtcNow.AddDays($Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
                # Preserve the legacy field so 4.7 can still decode configuration/update announcements.
                $existing=@($doc.pro.grants | Where-Object {$null -ne $_ -and $_.code.ToUpperInvariant() -eq $Code})
                $activationHash=''
                if ($existing.Count -gt 0) { $activationHash=[string]$existing[0].activationHash }
                if ($activationHash -notmatch '^[a-fA-F0-9]{64}$') {
                    $random=New-Object byte[] 32
                    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
                    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
                    $activationHash=([BitConverter]::ToString($random)).Replace('-','').ToLowerInvariant()
                }
                $rows+=[PSCustomObject]@{code=$Code;expiresAt=$until;features=@($Features | Select-Object -Unique);activationHash=$activationHash}
                $doc.pro.enabled=$true; $doc.pro.testing=$false
                Write-Host ('Access expires: '+$until)
            }
            $doc.pro.grants=@($rows)
        }
    }
    Write-Host 'Step 2/4: validating changes...'
    ValidatePersonalization $doc
    $config | Add-Member -NotePropertyName personalization -NotePropertyValue $doc -Force
    $epoch=[datetime]::SpecifyKind([datetime]'1970-01-01',[DateTimeKind]::Utc)
    $config.revision=[Math]::Max([long]([datetime]::UtcNow-$epoch).TotalSeconds,[long]$config.revision+1)
    $next=Join-Path $work 'configuration-pro.json'; WriteJson $next $config
    $check=Join-Path $work 'configuration-preflight.json';CopyStore $remote $check
    if ((Get-FileHash -LiteralPath $check -Algorithm SHA256).Hash -ne $hash) { throw 'Configuration changed. Run again; nothing published.' }
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup=Join-Path $work ('configuration-backup-'+$stamp+'.json');Copy-Item -LiteralPath $before -Destination $backup
    CopyStore $backup ('r2:appleipa-files/apple-store/backups/personalization/'+[IO.Path]::GetFileName($backup))
    Write-Host 'Step 3/4: publishing access changes...'
    CopyStore $next $remote
    Write-Host 'Step 4/4: verifying publication...'
    $readback=Join-Path $work 'configuration-verified.json'; CopyStore $remote $readback
    if ((Get-FileHash -LiteralPath $readback -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $next -Algorithm SHA256).Hash) { throw 'Read-back verification failed. Keep the backup and report the error.' }
    if ($Mode -eq 'Grant') {
        $receipt=Join-Path $work ('access-'+$Code+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
        [IO.File]::WriteAllText($receipt,('Device: '+$Code+[Environment]::NewLine+'Expires: '+$until+[Environment]::NewLine+'Status: enabled automatically in Apple Store 4.9'+[Environment]::NewLine),$utf8)
        Write-Host ('DONE. Pro enabled until '+$until) -ForegroundColor Green
        Write-Host 'The client only needs to refresh access in Apple Store. No activation code is required.'
    }
    Write-Host 'DONE. Themes and Pro settings updated; no IPA update was published.' -ForegroundColor Green
} catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;Write-Host $_.ScriptStackTrace;exit 1 }
