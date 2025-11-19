<#
.SYNOPSIS
    Prepares TSAC installer options and runs TSSACONSOLE installer silently.
#>

# ------------------------------------------------------------
# Modify Terminal Server temporary directory registry settings
# ------------------------------------------------------------

try {
    # ----------------------------
    # 1. Registry path and values
    # ----------------------------
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    $ValuesToSet = @{
        "PerSessionTempDir"      = 0
        "DeleteTempDirsOnExit"   = 0
    }

    # ----------------------------
    # 2. Ensure we can write to HKLM
    # ----------------------------
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        throw "[ERROR] Administrator privileges are required to modify HKLM registry keys."
    }

    # ----------------------------
    # 3. Set registry values
    # ----------------------------
    foreach ($name in $ValuesToSet.Keys) {
        Write-Host "[INFO] Setting $name to $($ValuesToSet[$name]) in $RegPath..." -ForegroundColor Cyan
        Set-ItemProperty -Path $RegPath -Name $name -Value $ValuesToSet[$name] -Type DWord -Force
        Write-Host "[OK] $name updated successfully." -ForegroundColor Green
    }

} catch {
    Write-Error "[WARN] Failed to update registry: $_"
}

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
# ----------------------------
$TempDir = "C:\Temp"
Write-Host "[INFO] Checking $TempDir folder..." -ForegroundColor Cyan
if (-not (Test-Path $TempDir)) {
    Write-Host "[INFO] Creating $TempDir ..." -ForegroundColor Cyan
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
# 2. Load JSON configuration
# ----------------------------
$ConfigFile = Join-Path $TempDir "tsas.config"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "[ERROR] Configuration file not found: $ConfigFile"
    exit 1
}

try {
    $Config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "[ERROR] Failed to parse configuration file as JSON: $($_.Exception.Message)"
    exit 1
}

$TSASInstallLocation = $Config.TSASInstallLocation
if (-not $TSASInstallLocation) {
    Write-Error "[ERROR] TSASInstallLocation not found in configuration file."
    exit 1
}

# ----------------------------
# 3. Append \TSAC to install location
# ----------------------------
$InstallRoot = Join-Path $TSASInstallLocation "TSAC"

# ----------------------------
# 4. Create tsac.ssi file
# ----------------------------
$SsiFile = Join-Path $TempDir "tsac.ssi"
$SsiContent = @"
-P installLocation=$InstallRoot
-J IS_UPGRADE=false
-A featureClientUtilities
-A featureNetworkShell
-A featureConfigurationManagerConsole
-A featureRCPUpgradeService
"@

try {
    $SsiContent | Out-File -FilePath $SsiFile -Encoding ASCII -Force
    Write-Host "[OK] Created SSI file at $SsiFile with install location: $InstallRoot" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to create SSI file: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# 5. Find TSSACONSOLE???-WIN64.exe
# ----------------------------
$BaseDir = "C:\Temp"

# Locate the extracted TSSA???-WIN64 folder
$ExtractedDir = Get-ChildItem -Path $BaseDir -Directory -Filter "TSSA???-WIN64" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $ExtractedDir) {
    Write-Host "[WARN] Could not locate extracted folder matching TSSA???-WIN64 in $BaseDir" -ForegroundColor Red
    Write-Host "[INFO] Please download the TSAC installer from support.bmc.com" -ForegroundColor Cyan
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

# Build the full installer path
$InstallerFolder = Join-Path $ExtractedDir.FullName "Disk1\files\installers\rcp"
$InstallerPattern = "TSSACONSOLE???-WIN64.exe"

$Installer = Get-ChildItem -Path $InstallerFolder -Filter $InstallerPattern -File -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $Installer) {
    Write-Host "[WARN] Could not find installer matching '$InstallerPattern' in $InstallerFolder" -ForegroundColor Red
    Write-Host "[INFO] Please download the TSAC installer from support.bmc.com" -ForegroundColor Cyan
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

Write-Host "[OK] Found installer: $($Installer.FullName)" -ForegroundColor Green

# ----------------------------
# 6. Run TSSACONSOLE installer silently
# ----------------------------
try {
    Write-Host "[INFO] Running TSAC installer silently..." -ForegroundColor Cyan
    Start-Process -FilePath $Installer.FullName -ArgumentList "-i silent -DOPTIONS_FILE=`"$SsiFile`"" -Wait -NoNewWindow
    Write-Host "[OK] TSAC installation completed successfully." -ForegroundColor Green
} catch {
    Write-Error "[ERROR] TSAC installation failed: $($_.Exception.Message)"
    exit 1
}

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
