param([string]$IpaPath, [string]$Name, [string]$Version, [string]$CatalogID='', [string]$DeviceCode='')
$ErrorActionPreference='Stop'
try {
    Write-Host 'Early Pro release uploader' -ForegroundColor Cyan
    if (!$IpaPath) { $IpaPath=(Read-Host 'Drop or paste the IPA file path').Trim('"') }
    if (!(Test-Path -LiteralPath $IpaPath -PathType Leaf)) { throw 'IPA file does not exist.' }
    if (!$Name) { $Name=Read-Host 'Application name' }
    if (!$Version) { $Version=Read-Host 'New version' }
    if (!$CatalogID) { $CatalogID=Read-Host 'Existing catalog ID, or Enter if unknown' }
    if (!$DeviceCode) { $DeviceCode=Read-Host 'Personal device code, or Enter for ALL Pro users' }
    $DeviceCode=($DeviceCode -replace '[\s-]','').ToUpperInvariant()
    if (!$Name -or $Name.Length -gt 150 -or !$Version -or $Version.Length -gt 50 -or $CatalogID.Length -gt 100) { throw 'Invalid release details.' }
    if ($DeviceCode -and $DeviceCode -notmatch '^[A-F0-9]{32}$') { throw 'Invalid personal device code.' }
    $info=Get-Item -LiteralPath $IpaPath
    if ($info.Length -lt 1024 -or $info.Length -ge 2GB) { throw 'IPA must be below 2 GB.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($info.FullName)
    try { if (@($zip.Entries | Where-Object {$_.FullName -match '(?i)^Payload/[^/]+\.app/Info\.plist$'}).Count -lt 1) { throw 'IPA does not contain an iPhone app.' } } finally { $zip.Dispose() }
    Get-Command gh -ErrorAction Stop | Out-Null
    $repo='Ellai95/apple-ipa-files';$tag='ipa-archive-1'
    $sha=(Get-FileHash -LiteralPath $info.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $id='early-'+[guid]::NewGuid().ToString('N').Substring(0,16)
    $asset='Pro-'+$id+'--'+$sha.Substring(0,16)+'.ipa'
    $work=Join-Path $PSScriptRoot 'pro-uploads';New-Item -ItemType Directory -Path $work -Force | Out-Null
    $staged=Join-Path $work $asset
    try { New-Item -ItemType HardLink -Path $staged -Target $info.FullName -ErrorAction Stop | Out-Null } catch { Copy-Item -LiteralPath $info.FullName -Destination $staged }
    Write-Host 'Step 1/2: uploading IPA to your GitHub release...'
    & gh release upload $tag $staged --repo $repo
    if ($LASTEXITCODE -ne 0) { throw 'GitHub upload failed. No catalog or early metadata was changed.' }
    $release=(& gh api ('repos/'+$repo+'/releases/tags/'+$tag) | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'GitHub verification failed.' }
    $pages=(& gh api ('repos/'+$repo+'/releases/'+$release.id+'/assets?per_page=100') --paginate --slurp | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'GitHub asset verification failed.' }
    $matches=@();foreach($page in $pages) { foreach($item in $page) { if ($item.name -eq $asset) { $matches+= $item } } }
    if ($matches.Count -ne 1 -or $matches[0].state -ne 'uploaded' -or [long]$matches[0].size -ne $info.Length -or $matches[0].digest -ne ('sha256:'+$sha)) { throw 'Uploaded IPA verification failed.' }
    $expected='https://github.com/'+$repo+'/releases/download/'+$tag+'/'+$asset
    if ($matches[0].browser_download_url -ne $expected) { throw 'Unexpected GitHub download URL.' }
    $audience=@();if ($DeviceCode) { $audience=@($DeviceCode) }
    $entry=[PSCustomObject]@{id=$id;catalogID=$CatalogID;name=$Name;version=$Version;ipaURL=$expected;notes='Раннее обновление для Pro. Общий каталог пока не изменён.';sizeBytes=[long]$info.Length;allowedCodes=@($audience);expiresAt=[datetime]::UtcNow.AddDays(30).ToString('yyyy-MM-ddTHH:mm:ssZ')}
    $metadata=Join-Path $work ($id+'.json')
    [IO.File]::WriteAllText($metadata,($entry | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    Write-Host 'Step 2/2: publishing early-access metadata only...'
    & (Join-Path $PSScriptRoot 'Admin-Pro.ps1') -Mode AddEarly -EarlyJson $metadata
    if ($LASTEXITCODE -ne 0) { throw 'Early metadata publication not confirmed; keep the metadata file.' }
    Remove-Item -LiteralPath $staged -Force
    Write-Host 'DONE. Early IPA added to Pro. The normal catalog and Apple Store update were not published.' -ForegroundColor Green
} catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;exit 1 }
