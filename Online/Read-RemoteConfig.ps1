# Check the public object when rclone returns no bytes (some versions use exit 0 for a missing object).
function Get-StorePublicConfiguration {
    param([string]$Uri = 'https://pub-d11175355ab34b9299fb0a916702bce7.r2.dev/apple-store/configuration.json')
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Cache-Control', 'no-cache, no-store')
    $response = $null
    try {
        $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
        $response = $client.GetAsync($Uri + $separator + 'check=' + [guid]::NewGuid().ToString()).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -eq 404) {
            Write-Host 'No configuration published yet. The IPA and first configuration will now be uploaded.' -ForegroundColor Yellow
            return $null
        }
        if ([int]$response.StatusCode -ne 200) { throw ('Cannot verify public configuration: HTTP ' + [int]$response.StatusCode + '. Nothing was published.') }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        if ($bytes.Length -eq 0 -or $bytes.Length -gt 524288) { throw 'Online configuration is empty or too large. Nothing was published.' }
        $value = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        if ($value.schemaVersion -ne 1 -or [int]$value.revision -lt 1) { throw 'Invalid online configuration. Nothing was published.' }
        return $value
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
    }
}

# Shared by the publisher scripts; compatible with Windows PowerShell 5.1.
# Read native stdout explicitly as UTF-8, without a temporary download file.
function Get-StoreRemoteConfiguration {
    param([Parameter(Mandatory = $true)][string]$Rclone)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Rclone
    $start.Arguments = 'cat "r2:appleipa-files/apple-store/configuration.json" --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (!$process.Start()) { throw 'Cannot start rclone.' }
        # Drain both streams concurrently so large output cannot block the child.
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'R2 configuration check timed out. Nothing was published.'
        }
        $remoteText = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        $code = $process.ExitCode
        if ($code -eq 3 -or $code -eq 4 -or ($code -eq 0 -and [string]::IsNullOrWhiteSpace($remoteText))) {
            return Get-StorePublicConfiguration
        }
        if ($code -ne 0) { throw ("Cannot read R2 configuration (rclone exit {0}). {1}" -f $code, $errorText.Trim()) }
        $value = $remoteText | ConvertFrom-Json -ErrorAction Stop
        if ($value.schemaVersion -ne 1 -or [int]$value.revision -lt 1) { throw 'Invalid online configuration. Nothing was published.' }
        return $value
    } finally { $process.Dispose() }
}
