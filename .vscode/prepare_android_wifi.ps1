$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $workspaceRoot '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Missing .env. Copy .env.example to .env before running the app.'
}

$envText = [System.IO.File]::ReadAllText($envPath)
$apiMatch = [regex]::Match($envText, '(?m)^API_BASE_URL=([^\r\n]*)')
$apiUri = $null
if (-not $apiMatch.Success -or -not [uri]::TryCreate($apiMatch.Groups[1].Value.Trim().Trim('"').Trim("'"), [UriKind]::Absolute, [ref]$apiUri) -or $apiUri.Scheme -notin @('http', 'https')) {
    throw 'API_BASE_URL must be an absolute HTTP/HTTPS URL.'
}

# Only local development addresses follow the current LAN address. Named or
# public backends are kept as configured, including their scheme, port and path.
$configuredAddress = $null
$isPrivateAddress = $false
if ([System.Net.IPAddress]::TryParse($apiUri.Host, [ref]$configuredAddress) -and
    $configuredAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
    $octets = $configuredAddress.GetAddressBytes()
    $isPrivateAddress = $octets[0] -eq 10 -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31)
}
if (-not ($apiUri.IsLoopback -or $isPrivateAddress)) {
    Write-Host 'Using the configured named/public backend without rewriting .env.'
    exit 0
}

$lanCandidates = @(
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up' -or
            $adapter.NetworkInterfaceType -notin @('Wireless80211', 'Ethernet') -or
            $adapter.Name -match 'vEthernet|WSL|WARP|VPN|Virtual|Bluetooth') { continue }
        $properties = $adapter.GetIPProperties()
        $gateways = @($properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address.ToString() -ne '0.0.0.0'
        })
        if ($gateways.Count -eq 0) { continue }
        foreach ($unicast in $properties.UnicastAddresses) {
            $address = $unicast.Address
            if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
                [System.Net.IPAddress]::IsLoopback($address) -or
                $address.ToString().StartsWith('169.254.')) { continue }
            [pscustomobject]@{
                Address = $address.ToString()
                Rank = $(if ($adapter.NetworkInterfaceType -eq 'Wireless80211') { 0 } else { 1 })
            }
        }
    }
)
$selectedLan = $lanCandidates | Sort-Object Rank, Address | Select-Object -First 1
if ($null -eq $selectedLan) {
    throw 'No active Wi-Fi/Ethernet IPv4 gateway was found. Connect to the LAN or use the USB launch profile.'
}

$apiBuilder = [System.UriBuilder]::new($apiUri)
$apiBuilder.Host = $selectedLan.Address
$updatedApi = $apiBuilder.Uri.AbsoluteUri
if (-not $apiUri.OriginalString.EndsWith('/') -and $apiUri.AbsolutePath -eq '/' -and -not $apiUri.Query -and -not $apiUri.Fragment) {
    $updatedApi = $updatedApi.TrimEnd('/')
}
$updatedText = [regex]::Replace($envText, '(?m)^API_BASE_URL=[^\r\n]*', [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)
    'API_BASE_URL=' + $updatedApi
})

# Keep an explicitly configured local socket in sync with the same backend.
# An empty REALTIME_URL continues to derive /ws in the app; remote URLs remain.
$socketMatch = [regex]::Match($envText, '(?m)^REALTIME_URL=([^\r\n]*)')
$socketUri = $null
if ($socketMatch.Success -and
    [uri]::TryCreate($socketMatch.Groups[1].Value.Trim().Trim('"').Trim("'"), [UriKind]::Absolute, [ref]$socketUri) -and
    $socketUri.Scheme -in @('ws', 'wss') -and $socketUri.Host -eq $apiUri.Host) {
    $socketBuilder = [System.UriBuilder]::new($socketUri)
    $socketBuilder.Host = $selectedLan.Address
    $updatedText = [regex]::Replace($updatedText, '(?m)^REALTIME_URL=[^\r\n]*', [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        'REALTIME_URL=' + $socketBuilder.Uri.AbsoluteUri
    })
}

if ($updatedText -cne $envText) {
    [System.IO.File]::WriteAllText($envPath, $updatedText, [System.Text.UTF8Encoding]::new($false))
}
Write-Host ('Wi-Fi backend prepared with current LAN address: ' + $selectedLan.Address)
