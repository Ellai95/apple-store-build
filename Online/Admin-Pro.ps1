param([ValidateSet('Publish','Grant','Revoke','Disable')][string]$Mode='Publish', [string]$Code='', [int]$Days=0, [string[]]$Features=@('premiumThemes','customWallpaper','noAds'))
$ErrorActionPreference='Stop'
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
function ValidatePersonalization($doc) {
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

try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $script:rclone='C:\rclone\rclone.exe'
    if (!(Test-Path -LiteralPath $rclone)) { $script:rclone=(Get-Command rclone -CommandType Application -ErrorAction Stop).Source }
    $before=Join-Path $work 'configuration-before.json'
    CopyStore $remote $before
    $hash=(Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash
    $config=ReadJson $before
    if ($config.schemaVersion -ne 1 -or $config.revision -lt 1) { throw 'Invalid current configuration.' }
    $oldDoc=$config.personalization
    if ($Mode -eq 'Publish') {
        $doc=ReadJson (Join-Path $PSScriptRoot 'Personalization.json')
        $doc.pro.grants=@()
        if ($null -ne $oldDoc) { $doc.pro.grants=@($oldDoc.pro.grants | Where-Object {$null -ne $_}) }
    } else {
        $doc=$oldDoc
        if ($null -eq $doc) { $doc=ReadJson (Join-Path $PSScriptRoot 'Personalization.json') }
        if ($Mode -eq 'Disable') { $doc.pro.enabled=$false; $doc.pro.testing=$false }
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
                $random=New-Object byte[] 16
                $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
                try { $rng.GetBytes($random) } finally { $rng.Dispose() }
                $activation=([BitConverter]::ToString($random)).Replace('-','')
                $sha=[Security.Cryptography.SHA256]::Create()
                try { $activationHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($activation)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
                $groups=@(); for($i=0;$i -lt 32;$i+=4) { $groups+= $activation.Substring($i,4) }
                $activationDisplay='PRO-'+($groups -join '-')
                $rows+=[PSCustomObject]@{code=$Code;expiresAt=$until;features=@($Features | Select-Object -Unique);activationHash=$activationHash}
                $doc.pro.enabled=$true; $doc.pro.testing=$false
                Write-Host ('Access expires: '+$until)
            }
            $doc.pro.grants=@($rows)
        }
    }
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
    CopyStore $next $remote
    $readback=Join-Path $work 'configuration-verified.json'; CopyStore $remote $readback
    if ((Get-FileHash -LiteralPath $readback -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $next -Algorithm SHA256).Hash) { throw 'Read-back verification failed. Keep the backup and report the error.' }
    if ($Mode -eq 'Grant') {
        $codeFile=Join-Path $work ('activation-'+$Code+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
        [IO.File]::WriteAllText($codeFile,('Device: '+$Code+[Environment]::NewLine+'Expires: '+$until+[Environment]::NewLine+'Activation: '+$activationDisplay+[Environment]::NewLine),$utf8)
        Write-Host ''
        Write-Host ('ACTIVATION CODE: '+$activationDisplay) -ForegroundColor Green
        Write-Host ('Saved locally: '+$codeFile)
        Write-Host 'Enter this code in Apple Store -> Pro -> Activate code. It works only on the registered device.'
    }
    Write-Host 'DONE. Themes and Pro settings updated; no IPA update was published.' -ForegroundColor Green
} catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;Write-Host $_.ScriptStackTrace;exit 1 }
