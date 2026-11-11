# Prepares the USB launch from .env, which stays the only file to edit.
#  - Backend on this PC (localhost, 127.0.0.1, 10.0.2.2 or one of this PC's IPs):
#    `adb reverse` maps the device's 127.0.0.1:<port> to this PC over the cable,
#    so the app uses http://127.0.0.1:<port> and never depends on Wi-Fi.
#  - Any other backend (domain, public server, another LAN machine): used as is.
# The result goes to .dart_tool/pos_launch.env, read by the USB launch profile.
param(
    [string]$EnvPath,
    [string]$OutPath,
    # Writes the launch file without touching ADB (for checking the result).
    [switch]$SkipAdb
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvPath) { $EnvPath = Join-Path $workspaceRoot '.env' }
if (-not $OutPath) { $OutPath = Join-Path $workspaceRoot '.dart_tool\pos_launch.env' }
if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw 'Missing .env. Copy .env.example to .env before running the app.'
}

$envText = [System.IO.File]::ReadAllText($EnvPath)

function Get-EnvUri([string]$key, [string[]]$schemes) {
    $match = [regex]::Match($envText, "(?m)^$key=([^\r\n]*)")
    if (-not $match.Success) { return $null }
    $raw = $match.Groups[1].Value.Trim().Trim('"').Trim("'")
    $uri = $null
    if ([uri]::TryCreate($raw, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in $schemes) {
        return $uri
    }
    return $null
}

function Set-EnvValue([string]$text, [string]$key, [string]$value) {
    $pattern = "(?m)^$key=[^\r\n]*"
    if ([regex]::IsMatch($text, $pattern)) {
        return [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            "$key=$value"
        })
    }
    return $text.TrimEnd() + [Environment]::NewLine + "$key=$value" + [Environment]::NewLine
}

$apiUri = Get-EnvUri 'API_BASE_URL' @('http', 'https')
if ($null -eq $apiUri) {
    throw 'API_BASE_URL in .env must be an absolute HTTP/HTTPS URL.'
}

# Is the backend running on this PC?
$thisPcAddresses = @(
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up') { continue }
        foreach ($unicast in $adapter.GetIPProperties().UnicastAddresses) {
            $unicast.Address.ToString()
        }
    }
)
$isOnThisPc = $apiUri.IsLoopback -or
    $apiUri.Host -eq '10.0.2.2' -or
    $thisPcAddresses -contains $apiUri.Host

$launchText = $envText
if ($isOnThisPc) {
    $port = $apiUri.Port
    $builder = [System.UriBuilder]::new($apiUri)
    $builder.Host = '127.0.0.1'
    $usbApi = $builder.Uri.AbsoluteUri
    if ($apiUri.AbsolutePath -eq '/' -and -not $apiUri.OriginalString.EndsWith('/')) {
        $usbApi = $usbApi.TrimEnd('/')
    }
    $launchText = Set-EnvValue $launchText 'API_BASE_URL' $usbApi

    # A WebSocket URL on the same local backend is derived from the API URL
    # instead (empty REALTIME_URL → /ws), so it also goes through the cable.
    $socketUri = Get-EnvUri 'REALTIME_URL' @('ws', 'wss')
    if ($null -ne $socketUri -and $socketUri.Host -eq $apiUri.Host) {
        $launchText = Set-EnvValue $launchText 'REALTIME_URL' ''
    }
}

$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
[System.IO.File]::WriteAllText($OutPath, $launchText, [System.Text.UTF8Encoding]::new($false))

if (-not $isOnThisPc) {
    Write-Host "Using the backend from .env: $($apiUri.AbsoluteUri)"
    exit 0
}
if ($SkipAdb) {
    Write-Host "Backend on this PC: app uses $usbApi over USB (ADB skipped)."
    exit 0
}

$localProperties = Join-Path $workspaceRoot 'android\local.properties'
$sdkCandidates = @()

if (Test-Path -LiteralPath $localProperties) {
    $sdkLine = Get-Content -LiteralPath $localProperties -Encoding UTF8 |
        Where-Object { $_ -match '^sdk\.dir=' } |
        Select-Object -First 1
    if ($sdkLine) {
        $sdkCandidates += ($sdkLine.Substring(8) -replace '\\\\', '\' -replace '\\:', ':')
    }
}

$sdkCandidates += @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
if ($env:LOCALAPPDATA) {
    $sdkCandidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}

$adbExecutable = $null
foreach ($sdkCandidate in $sdkCandidates) {
    if ([string]::IsNullOrWhiteSpace($sdkCandidate)) { continue }
    $adbCandidate = Join-Path $sdkCandidate 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adbCandidate) {
        $adbExecutable = $adbCandidate
        break
    }
}

if (-not $adbExecutable) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCommand) { $adbExecutable = $adbCommand.Source }
}
if (-not $adbExecutable) {
    throw 'ADB was not found. Install Android SDK platform-tools or set sdk.dir in android/local.properties.'
}

# Works for a physical device (preferred) or an emulator.
# Reapply on every F5: the mapping is lost after disconnecting/restarting ADB.
$readyDevices = @(
    & $adbExecutable devices |
        Select-Object -Skip 1 |
        Where-Object { $_ -match '^\S+\s+device$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
)
if ($readyDevices.Count -eq 0) {
    throw 'No Android device found. Start an emulator, or connect a phone with USB debugging enabled and accept its authorization prompt, then retry.'
}
$physicalDevices = @($readyDevices | Where-Object { $_ -notlike 'emulator-*' })
$targetDevice = if ($physicalDevices.Count -gt 0) { $physicalDevices[0] } else { $readyDevices[0] }

& $adbExecutable -s $targetDevice reverse "tcp:$port" "tcp:$port"
if ($LASTEXITCODE -ne 0) {
    throw "adb reverse failed on $targetDevice."
}

Write-Host "Backend ready at $usbApi on $targetDevice. Keep the device connected and the backend running."
