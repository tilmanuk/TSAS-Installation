<#
.SYNOPSIS
    Create bao-repo.ssi from c:\temp\tsas.config and run BAO repo silent installer.
    Robust handling to avoid Write-Host parser/formatting issues.
#>

# ----------------------------
# Configuration
# ----------------------------
$TempDir         = "C:\Temp"
$ConfigFile      = Join-Path $TempDir "tsas.config"
$SilentFile      = Join-Path $TempDir "bao-repo.ssi"
$InstallerPrefix = "windows_bao_server_installer_"
$InstallLog      = Join-Path $TempDir "bao-repo-install.log"

# ----------------------------
# Output helpers (ASCII-safe)
# ----------------------------
function Write-Info([string]$msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn([string]$msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Helper to stringify possibly-array objects
function ToStringSafe($obj) {
    if ($null -eq $obj) { return "" }
    if ($obj -is [System.Array] -or $obj -is [System.Collections.IEnumerable]) {
        return ($obj | ForEach-Object { $_.ToString() }) -join ","
    } else {
        return $obj.ToString()
    }
}

# ----------------------------
# 1. Ensure Temp exists and writable
# ----------------------------
Write-Info ("Checking {0} folder..." -f (ToStringSafe $TempDir))
if (-not (Test-Path $TempDir)) {
    Write-Info ("Creating {0}..." -f (ToStringSafe $TempDir))
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

try {
    $TestFile = Join-Path $TempDir "write_test.tmp"
    "test" | Out-File -FilePath $TestFile -ErrorAction Stop -Encoding ASCII
    Remove-Item $TestFile -Force
    Write-OK ("Verified write access to {0}" -f (ToStringSafe $TempDir))
} catch {
    Write-Err ("Cannot write to {0}. Please run as Administrator." -f (ToStringSafe $TempDir))
    exit 1
}

# ----------------------------
# 2. Load config and list values (diagnostic)
# ----------------------------
if (-not (Test-Path $ConfigFile)) {
    Write-Err ("Config file not found: {0}" -f (ToStringSafe $ConfigFile))
    exit 1
}

try {
    $Config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
} catch {
    Write-Err ("Failed to parse JSON config file: {0}" -f (ToStringSafe $ConfigFile))
    exit 1
}

# ----------------------------
# Extract required fields and construct FQDN and URLs
# ----------------------------
$Hostname          = ToStringSafe $Config.Hostname
$IPAddress         = ToStringSafe $Config.IPAddress
$EncryptedPassword = ToStringSafe $Config.EncryptedPassword
$Domain            = ToStringSafe $Config.Domain
$TSASInstallLocation = ToStringSafe $Config.TSASInstallLocation
$InstallPath = Join-Path $TSASInstallLocation "AO\Repo"

# Create fully-qualified domain name (FQDN)
$FQDN = "$Hostname.$Domain"

# Update URLs to use FQDN
$EmbeddedRSSOURL = "https://" + $FQDN + ":8443"
$AOWebserverURL  = "https://" + $FQDN + ":28080/baorepo"

Write-Info ("Loaded configuration from {0}" -f (ToStringSafe $ConfigFile))
Write-Info ("  Hostname  : {0}" -f $Hostname)
Write-Info ("  IPAddress : {0}" -f $IPAddress)
Write-Info ("  Domain    : {0}" -f $Domain)
Write-Info ("  FQDN      : {0}" -f $FQDN)
Write-Info ("  Encrypted : {0}" -f ([bool]$EncryptedPassword))
Write-Info ("  RSSO URL  : {0}" -f $EmbeddedRSSOURL)
Write-Info ("  AO Repo URL : {0}" -f $AOWebserverURL)
Write-Info ("  Install Path : {0}" -f $InstallPath)

if ([string]::IsNullOrWhiteSpace($Hostname) -or [string]::IsNullOrWhiteSpace($IPAddress) -or [string]::IsNullOrWhiteSpace($EncryptedPassword)) {
    Write-Err "Required values missing in tsas.config (Hostname, IPAddress, EncryptedPassword)."
    exit 1
}

# After reading config and setting $Hostname:


# ----------------------------
# 3. Create bao-repo.ssi (overwrite if exists)
# ----------------------------
if (Test-Path $SilentFile) {
    Write-Warn ("Existing {0} found. Removing..." -f (ToStringSafe $SilentFile))
    Remove-Item $SilentFile -Force -ErrorAction SilentlyContinue
}

Write-Info ("Generating silent install file: {0}" -f (ToStringSafe $SilentFile))

$ssiContent = @"
-P installLocation=$InstallPath
-J AO_ADMIN_USERNAME=aoadmin
-J AO_ADMIN_PASSWORD=$EncryptedPassword
-J AO_WEBSERVER_PROTOCOL=https
-J AO_INSTALL_TYPE=install_new
-J AO_INSTALLING_FEATURES=REPO,WEBSERVER
-J AO_ENVIRONMENT_NAME=TSO Environment
-J AO_GRID_NAME=MyGrid
-J AO_GRID_TYPE=dev
-J AO_GRID_LOGGING_LEVEL=debug
-J AO_START_SERVER_ON_SUCCESS=true
-J AO_OCP_DEPLOYMENT_CONTEXT=baoocp
-J AO_PEER_NAME=CDP
-J AO_PEER_NET_CONFIG_CDP_CONTEXT=baocdp
-J AO_PEER_NET_CONFIG_CDP_PORT=8080
-J AO_REPOSITORY_PORT=28080
-J AO_REPOSITORY_USER_NAME=admin
-J AO_PEER_NET_CONFIG_PEER_NAME=CDP
-J AO_PEER_NET_CONFIG_PROTOCOL=https
-J AO_SECURITY_ACTIVE=true
-J AO_SECURITY_WEB_PROTOCOL=https
-J AO_REPOSITORY_HA_IPADDRESS=$IPAddress
-J AO_CDP_HA_IPADDRESS=$IPAddress
-J AO_HACDP_HA_IPADDRESS=$IPAddress
-J AO_REPOSITORY_HA_PORT=28090
-J AO_CDP_HA_PORT=38090
-J AO_HACDP_HA_PORT=38091
-J AO_WEBSERVER_PORT=28080
-J AO_WEBSERVER_SHUTDOWN_PORT=28050
-J AO_PEER_COMM_PORT=61719
-J AO_WEBSERVER_HOST=$FQDN
-J AO_RSSO_COOKIE_DOMAIN=micwilli.local
-J AO_USE_EMBEDDED_RSSO=true
-J AO_USE_EXTERNAL_RSSO=false
-J AO_RSSO_VERSION=20.02
-J AO_EMBEDDED_RSSO_URL=$EmbeddedRSSOURL
-J AO_WEBSERVER_URL=$AOWebserverURL
-J AO_WINDOWS_SERVICE_NAME=BAO-REPO
-J AO_WINDOWS_SERVICE_DISPLAY_NAME=TrueSight Orchestration Repository
"@

try {
    $ssiContent | Out-File -FilePath $SilentFile -Encoding ASCII -Force
    Write-OK ("Created bao-repo.ssi at {0}" -f (ToStringSafe $SilentFile))
    Write-Info "Preview (first 6 lines):"
    Get-Content -Path $SilentFile -TotalCount 6 | ForEach-Object { Write-Host "  $_" }
} catch {
    Write-Err ("Failed to write {0}" -f (ToStringSafe $SilentFile))
    exit 1
}

# ----------------------------
# 4. Locate installer directory (windows_bao_server_installer_*_*_*)
# ----------------------------
Write-Info ("Searching for installer directory under {0} with prefix '{1}'" -f (ToStringSafe $TempDir), $InstallerPrefix)

$InstallerDir = Get-ChildItem -Path $TempDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like ("$InstallerPrefix*") } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $InstallerDir) {
    Write-Err ("Could not find installer folder matching prefix '{0}' in {1}" -f $InstallerPrefix, (ToStringSafe $TempDir))
    exit 1
}

$InstallerDirPath = ToStringSafe $InstallerDir.FullName
$SetupCmd = Join-Path $InstallerDirPath "setup.cmd"

if (-not (Test-Path $SetupCmd)) {
    Write-Err ("Installer executable not found: {0}" -f $SetupCmd)
    exit 1
}

Write-OK ("Installer found at: {0}" -f $SetupCmd)
Write-Info ("Installer folder: {0}" -f $InstallerDirPath)

# ----------------------------
# 5. Run installer via cmd.exe and capture output to $InstallLog
# ----------------------------
# ----------------------------
# Run Installer
# ----------------------------
Write-Host "[INFO] Searching for installer directory in C:\Temp..." -ForegroundColor Cyan
$InstallerDir = Get-ChildItem -Path "C:\Temp" -Directory | Where-Object { $_.Name -match '^windows_bao_server_installer_\d+_\d+_\d+$' } | Select-Object -First 1

if (-not $InstallerDir) {
    Write-Host "[ERROR] Could not find installer folder in C:\Temp matching windows_bao_server_installer_??_?_?? pattern." -ForegroundColor Red
    exit 1
}

$InstallerPath = Join-Path $InstallerDir.FullName "setup.cmd"
$OptionsFile = "C:\Temp\bao-repo.ssi"
$LogFile = "C:\Temp\bao-repo-install.log"

# Construct the exact command line we’ll run
$CmdLine = "`"$InstallerPath`" -i silent -DOPTIONS_FILE=`"$OptionsFile`""

Write-Host "[INFO] Installer found at: $InstallerPath" -ForegroundColor Cyan
Write-Host "[INFO] About to run the following command in cmd.exe:" -ForegroundColor Yellow
Write-Host "       $CmdLine" -ForegroundColor White
Write-Host "[INFO] Running installer silently..." -ForegroundColor Cyan

# Start the process
Start-Process -FilePath $SetupCmd -ArgumentList "-i silent -DOPTIONS_FILE=`"$OptionsFile`"" -Wait

# Check exit code (if needed)
if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
    Write-Host "[OK] Installation completed successfully." -ForegroundColor Green
} else {
    Write-Host "[ERROR] Installation finished with exit code $LASTEXITCODE. See log: $LogFile" -ForegroundColor Red
}

# ----------------------------
# Check and wait for BAO-REPO service
# ----------------------------
$ServiceName = "BAO-REPO"
$WaitTimeoutSeconds = 90
$WaitInterval = 3  # seconds between checks
$Elapsed = 0

try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop

    if ($service.Status -eq 'Running') {
        Write-Host "[OK] Service '$ServiceName' is running." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Waiting for service '$ServiceName' to start..." -ForegroundColor Cyan
        while ($service.Status -ne 'Running' -and $Elapsed -lt $WaitTimeoutSeconds) {
            Start-Sleep -Seconds $WaitInterval
            $Elapsed += $WaitInterval
            # Refresh service status
            $service = Get-Service -Name $ServiceName
            Write-Host ("`rWaiting: {0}/{1} seconds..." -f $Elapsed, $WaitTimeoutSeconds) -NoNewline
        }
        Write-Host ""  # finalize the line

        if ($service.Status -eq 'Running') {
            Write-Host "[OK] Service '$ServiceName' is now running." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Service '$ServiceName' failed to start after $WaitTimeoutSeconds seconds. Current status: $($service.Status)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "[ERROR] Service '$ServiceName' not found." -ForegroundColor Red
}

# ----------------------------
# 7. Display post-installation login instructions
# ----------------------------

# Build login site URL properly using concatenation
$LoginURL = "https://" + $FQDN + ":28080/ux"
$Username = "AOAdmin"
$Password = $Config.AdminPassword  # from tsas.config

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Installation verification complete." -ForegroundColor Cyan
Write-Host "Before running the next script, please log into the BAO repository:" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  Site     : {0}" -f $LoginURL) -ForegroundColor Yellow
Write-Host ("  Username : {0}" -f $Username) -ForegroundColor Yellow
Write-Host ("  Password : {0}" -f $Password) -ForegroundColor Yellow
Write-Host ""
Write-Host "Open the above site in a web browser and verify that you can successfully log in." -ForegroundColor Cyan
Write-Host "Once confirmed, proceed with the next installation or configuration step." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

Write-OK "BAO Repository silent installation script completed."

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
