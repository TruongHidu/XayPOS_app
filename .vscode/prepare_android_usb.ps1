$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
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

# -d selects a physical USB device and fails when more than one is connected.
# Reapply on every F5: the mapping is lost after disconnecting/restarting ADB.
& $adbExecutable -d reverse tcp:8080 tcp:8080
if ($LASTEXITCODE -ne 0) {
    throw 'USB setup failed. Connect one Android device, enable USB debugging and accept its authorization prompt, then retry.'
}

Write-Host 'USB backend ready at http://127.0.0.1:8080. Keep the USB cable connected and the backend running.'
