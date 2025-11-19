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
    Write-Host "[OK] Verified write access to $TempDir" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Cannot write to $TempDir. Please run as Administrator."
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
        Write-Warning "[WARN] Current user ($DetectedUser) is not in local Administrators group."
    } else {
        Write-Host "[OK] Current user ($DetectedUser) is a local Administrator." -ForegroundColor Green
    }
} catch {
    Write-Warning "[WARN] Failed to check Administrator membership."
}

# ----------------------------
# 3. Detect DNS Domain
# ----------------------------
try {
    $dnsDomain = (Get-DnsClient | Where-Object { $_.ConnectionSpecificSuffix -ne "" } | Select-Object -First 1).ConnectionSpecificSuffix
    if (-not $dnsDomain) {
        Write-Warning "[WARN] Could not automatically detect DNS domain. Please enter manually."
        $dnsDomain = Read-Host "Enter DNS domain for this host"
    }
    Write-Host "[INFO] Detected DNS domain: $dnsDomain" -ForegroundColor Cyan

    $inputDomain = Read-Host "DNS Domain for this host [$dnsDomain]"
    if (-not [string]::IsNullOrWhiteSpace($inputDomain)) {
        $dnsDomain = $inputDomain
    }
} catch {
    Write-Warning "[WARN] Failed to detect DNS domain automatically. Please enter manually."
    $dnsDomain = Read-Host "Enter DNS domain for this host"
}

# ----------------------------
# 4. Helper: generate safe structured password
# ----------------------------
function New-SafePassword {
    param(
        [int]$BlockLength = 5,
        [int]$Blocks = 3
    )

    $upper = [char[]](65..90)
    $lower = [char[]](97..122)
    $digit = [char[]](48..57)
    $special = [char[]]('!','@','#','$','%','^','&','*')
    $all = $upper + $lower + $digit + $special

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    function Get-RandomChar([char[]]$set) {
        $b = New-Object 'byte[]' 1
        $rng.GetBytes($b)
        return $set[$b[0] % $set.Length]
    }

    do {
        $passwordBlocks = @()
        for ($i = 1; $i -le $Blocks; $i++) {
            $blockChars = @()
            for ($j = 1; $j -le $BlockLength; $j++) {
                $blockChars += Get-RandomChar $all
            }
            $passwordBlocks += -join $blockChars
        }
        $pw = $passwordBlocks -join '-'

        $hasUpper = $pw -match '[A-Z]'
        $hasLower = $pw -match '[a-z]'
        $hasDigit = $pw -match '\d'
        $hasSpecial = $pw -match '[!@#$%^&*]'
    } while (-not ($hasUpper -and $hasLower -and $hasDigit -and $hasSpecial))

    return $pw
}

$GeneratedPassword = New-SafePassword
Write-Host "Generated Password: $GeneratedPassword"

# ----------------------------
# 5. Collect configuration interactively
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
$Config.SQLDBName = Prompt-ConfigValue "SQL Database name" "tsas"
$Config.AdminUser = Prompt-ConfigValue "Admin Username" "bladmin"
$Config.AdminPassword = Prompt-ConfigValue "Admin Password" $GeneratedPassword
$Config.RSCDUser = Prompt-ConfigValue "RSCD User" $DetectedUser
$Config.TSASInstallLocation = Prompt-ConfigValue "TSAS Install Location" "C:\Program Files\BMC Software"
$Config.HelixURL = Prompt-ConfigValue "Helix Portal URL" "https://helixdemoashXXXX-itom-demo.onbmc.com"
$Config.Domain = $dnsDomain

# ----------------------------
# 6. Save configuration to file
# ----------------------------
try {
    $Config | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigFile -Encoding ASCII -Force
    Write-Host "[OK] Configuration saved to $ConfigFile" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to save configuration."
    exit 1
}

# ----------------------------
# 7. Write SQL Configuration File (SQLConfig.ini)
# ----------------------------
$SQLConfigPath = Join-Path $TempDir "SQLConfig.ini"
$InstanceName = $Config.SQLInstance
$SAPassword   = $Config.AdminPassword

if (-not $InstanceName -or -not $SAPassword) {
    Write-Error "[ERROR] SQL instance name or SA password missing. Cannot create SQLConfig.ini."
    exit 1
}

$SQLConfigContent = @"
; Microsoft SQL Server Configuration file
[OPTIONS]
ACTION="Install"
FEATURES=SQL
INSTANCENAME="$InstanceName"
SAPWD="$SAPassword"
SECURITYMODE=SQL
TCPENABLED=1
"@

try {
    $SQLConfigContent | Out-File -FilePath $SQLConfigPath -Encoding ASCII -Force
    Write-Host "[OK] SQL configuration file created: $SQLConfigPath" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to write SQLConfig.ini."
    exit 1
}

Write-Host "[INFO] TSAS configuration collection complete. Domain detected/saved: $($Config.Domain)" -ForegroundColor Cyan

# ----------------------------
# Determine next script to run
# ----------------------------

# Get the current script name
$CurrentScript = $MyInvocation.MyCommand.Name

# Extract the first character (letter)
$CurrentLetter = $CurrentScript.Substring(0,1).ToLower()

# Calculate the next alphabetical letter
$NextLetter = [char](([int][char]$CurrentLetter) + 1)

# Get this script's folder
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

# Look for a script in the same folder that starts with the next letter
$NextScript = Get-ChildItem -Path $ScriptFolder -Filter "$NextLetter*.ps1" |
              Sort-Object Name |
              Select-Object -First 1

Write-Host ""
Write-Host "-------------------------------------------------" -ForegroundColor Cyan
Write-Host "Script finished: $CurrentScript" -ForegroundColor Green

if ($NextScript) {
    Write-Host "Next script to run is:" -ForegroundColor Yellow
    Write-Host "$($NextScript.Name)" -ForegroundColor Cyan
} else {
    Write-Host "No next script found for letter '$NextLetter'." -ForegroundColor Red
    Write-Host "This may have been the final script." -ForegroundColor Yellow
}

Write-Host "-------------------------------------------------" -ForegroundColor Cyan


