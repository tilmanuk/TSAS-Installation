<#
.SYNOPSIS
    Collects TSAS installation configuration interactively and saves to c:\temp\tsas.config
#>

# ----------------------------
# Configuration
# ----------------------------
$TempDir = "C:\Temp"
$ConfigFile = Join-Path $TempDir "tsas.config"

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
# ----------------------------
Write-Host "Checking $TempDir folder..."
if (-not (Test-Path $TempDir)) {
    Write-Host "Creating $TempDir ..."
    New-Item -Path $TempDir -ItemType Directory | Out-Null
}

try {
    $TestFile = Join-Path $TempDir "write_test.tmp"
    "test" | Out-File -FilePath $TestFile -ErrorAction Stop
    Remove-Item $TestFile -Force
    Write-Host "✅ Verified write access to $TempDir"
} catch {
    Write-Error "❌ Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 2. Detect current system info
# ----------------------------
$Hostname = $env:COMPUTERNAME

# Get primary IPv4 address (skip loopback and APIPA)
try {
    $IPAddress = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne "127.0.0.1" -and -not $_.IPAddress.StartsWith("169.254.") } |
        Select-Object -ExpandProperty IPAddress -First 1

    if (-not $IPAddress) { $IPAddress = "127.0.0.1" }
} catch {
    $IPAddress = "127.0.0.1"
}
Write-Host "Detected server IP Address: $IPAddress"

# Logged in user without domain prefix
try {
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $DetectedUserFull = $currentIdentity.Name
    if ($DetectedUserFull -like "*\*") {
        $DetectedUser = $DetectedUserFull.Split('\')[-1]
    } else {
        $DetectedUser = $DetectedUserFull
    }
} catch {
    $DetectedUser = $env:USERNAME
}

# Verify admin membership
try {
    $isAdmin = ([bool](([System.Security.Principal.WindowsPrincipal]::new(
        [System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)))
    if (-not $isAdmin) {
        Write-Warning "⚠️ Current user ($DetectedUser) is not in local Administrators group."
    } else {
        Write-Host "✅ Current user ($DetectedUser) is a local Administrator."
    }
} catch {
    Write-Warning "⚠️ Failed to check Administrator membership: $($_.Exception.Message)"
}

# ----------------------------
# 3. Helper: generate safe password
# ----------------------------
function New-SafePassword {
    param([int]$Length = 12)
    $chars = @()
    $chars += [char[]](65..90)    # A-Z
    $chars += [char[]](97..122)   # a-z
    $chars += [char[]](48..57)    # 0-9

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object 'byte[]' $Length
    $rng.GetBytes($bytes)
    $pw = -join ($bytes | ForEach-Object { $chars[ $_ % $chars.Length ] })
    return $pw
}
$GeneratedPassword = New-SafePassword 12

# ----------------------------
# 4. Collect configuration interactively
# ----------------------------
function Prompt-ConfigValue {
    param([string]$PromptText, [string]$Default)
    $response = Read-Host "$PromptText [$Default]"
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    else { return $response }
}

$Config = @{}
$Config.Hostname = Prompt-ConfigValue "Hostname" $Hostname
$Config.IPAddress = Prompt-ConfigValue "IP Address" $IPAddress
$Config.SQLInstance = Prompt-ConfigValue "SQL Server Named Instance" "tsas"
$Config.SQLInstance = Prompt-ConfigValue "SQL Database name" "tsas"
$Config.AdminUser = Prompt-ConfigValue "Admin Username" "bladmin"
$Config.AdminPassword = Prompt-ConfigValue "Admin Password" $GeneratedPassword
$Config.RSCDUser = Prompt-ConfigValue "RSCD User" $DetectedUser
$Config.TSASInstallLocation = Prompt-ConfigValue "TSAS Install Location" "C:\Program Files\BMC Software\TSAS"
$Config.PatchRepository = Prompt-ConfigValue "Patch Repository" "C:\patches"

# ----------------------------
# 5. Save configuration to file
# ----------------------------
try {
    $Config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigFile -Encoding UTF8 -Force
    Write-Host "✅ Configuration saved to $ConfigFile"
} catch {
    Write-Error "❌ Failed to save configuration: $($_.Exception.Message)"
    exit 1
}