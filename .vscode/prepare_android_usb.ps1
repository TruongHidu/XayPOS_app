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

# Works for a physical device (preferred) or an emulator: adb reverse maps the
# device's 127.0.0.1:8080 to this PC's port 8080 in both cases.
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

& $adbExecutable -s $targetDevice reverse tcp:8080 tcp:8080
if ($LASTEXITCODE -ne 0) {
    throw "adb reverse failed on $targetDevice."
}

Write-Host "Backend ready at http://127.0.0.1:8080 on $targetDevice. Keep the device connected and the backend running."
