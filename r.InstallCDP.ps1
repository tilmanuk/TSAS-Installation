<#
.SYNOPSIS
    Create bao-cdp.ssi from c:\temp\tsas.config and run BAO CDP silent installer.
    Mirrors the BAO Repo installer script, modified for CDP installation.
#>

# ----------------------------
# Configuration
# ----------------------------
$TempDir         = "C:\Temp"
$ConfigFile      = Join-Path $TempDir "tsas.config"
$SilentFile      = Join-Path $TempDir "bao-cdp.ssi"
$InstallerPrefix = "windows_bao_server_installer_"
$InstallLog      = Join-Path $TempDir "bao-cdp-install.log"

# ----------------------------
# Output helpers
# ----------------------------
function Write-Info([string]$msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn([string]$msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

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
# 2. Load config and extract values
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

$Hostname          = ToStringSafe $Config.Hostname
$IPAddress         = ToStringSafe $Config.IPAddress
$EncryptedPassword = ToStringSafe $Config.EncryptedPassword
$Domain            = ToStringSafe $Config.Domain

# Construct FQDN and CDP URL
$FQDN   = "$Hostname.$Domain"
$CDPURL = "https://" + $FQDN + ":38080/baocdp"

Write-Info ("Loaded configuration from {0}" -f (ToStringSafe $ConfigFile))
Write-Info ("  Hostname  : {0}" -f $Hostname)
Write-Info ("  IPAddress : {0}" -f $IPAddress)
Write-Info ("  Domain    : {0}" -f $Domain)
Write-Info ("  FQDN      : {0}" -f $FQDN)
Write-Info ("  Encrypted : {0}" -f ([bool]$EncryptedPassword))
Write-Info ("  CDP URL   : {0}" -f $CDPURL)

if ([string]::IsNullOrWhiteSpace($Hostname) -or [string]::IsNullOrWhiteSpace($IPAddress) -or [string]::IsNullOrWhiteSpace($EncryptedPassword)) {
    Write-Err "Required values missing in tsas.config (Hostname, IPAddress, EncryptedPassword)."
    exit 1
}

# ----------------------------
# 3. Create bao-cdp.ssi
# ----------------------------
if (Test-Path $SilentFile) {
    Write-Warn ("Existing {0} found. Removing..." -f (ToStringSafe $SilentFile))
    Remove-Item $SilentFile -Force -ErrorAction SilentlyContinue
}

Write-Info ("Generating silent install file: {0}" -f (ToStringSafe $SilentFile))

$ssiContent = @"
-P installLocation=C:\Program Files\BMC Software\AO\CDP
-J AO_INSTALL_TYPE=install_new
-J AO_INSTALLING_FEATURES=CDP
-J AO_START_SERVER_ON_SUCCESS=true
-J AO_USE_EMBEDDED_RSSO=true
-J AO_USE_EXTERNAL_RSSO=false
-J AO_RSSO_COOKIE_DOMAIN=$Domain
-J AO_WEBSERVER_PORT=38080
-J AO_WEBSERVER_SHUTDOWN_PORT=38050
-J AO_WEBSERVER_PROTOCOL=https
-J AO_CDP_IS_PRIMARY=true
-J AO_ENVIRONMENT_NAME=BAO Environment
-J AO_GRID_NAME=MyGrid
-J AO_GRID_TYPE=dev
-J AO_GRID_LOGGING_LEVEL=debug
-J AO_PEER_NAME=CDP
-J AO_CERT_PRINCIPAL=BMCHelix
-J AO_CERT_PASSWORD=$EncryptedPassword
-J AO_PEER_COMM_PORT=61719
-J AO_REPOSITORY_HOST=$FQDN
-J AO_REPOSITORY_PROTOCOL=https
-J AO_REPOSITORY_PORT=28080
-J AO_ADMIN_USERNAME=aoadmin
-J AO_ADMIN_PASSWORD=$EncryptedPassword
-J AO_START_SERVER_ON_SUCCESS=true
-J AO_WEBSERVER_HOST=$FQDN
-J AO_WEBSERVER_URL=$CDPURL
-J AO_REPOSITORY_HA_IPADDRESS=$IPAddress
-J AO_REPOSITORY_HA_PORT=28090
-J AO_CDP_HA_IPADDRESS=$IPAddress
-J AO_CDP_HA_PORT=38090
-J AO_CASSANDRA_SERVER_CONFIG=false
-J AO_WINDOWS_SERVICE_NAME=BAO-CDP
-J AO_WINDOWS_SERVICE_DISPLAY_NAME=TrueSight Orchestration CDP
"@

try {
    $ssiContent | Out-File -FilePath $SilentFile -Encoding ASCII -Force
    Write-OK ("Created bao-cdp.ssi at {0}" -f (ToStringSafe $SilentFile))
    Write-Info "Preview (first 6 lines):"
    Get-Content -Path $SilentFile -TotalCount 6 | ForEach-Object { Write-Host "  $_" }
} catch {
    Write-Err ("Failed to write {0}" -f (ToStringSafe $SilentFile))
    exit 1
}

# ----------------------------
# 4. Locate installer directory
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
# 5. Run CDP Installer
# ----------------------------
$OptionsFile = $SilentFile
$CmdLine = "`"$SetupCmd`" -i silent -DOPTIONS_FILE=`"$OptionsFile`""

Write-Info "About to run silent installation command:"
Write-Host "       $CmdLine" -ForegroundColor Yellow

Start-Process -FilePath $SetupCmd -ArgumentList "-i silent -DOPTIONS_FILE=`"$OptionsFile`"" -Wait

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
    Write-OK "CDP installation completed successfully."
} else {
    Write-Err ("Installation finished with exit code $LASTEXITCODE. See log: $InstallLog")
}

# ----------------------------
# 6. Check and wait for BAO-CDP service
# ----------------------------
$ServiceName = "BAO-CDP"
$WaitTimeoutSeconds = 90
$WaitInterval = 3
$Elapsed = 0

try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        Write-OK ("Service '$ServiceName' is running.")
    } else {
        Write-Info ("Waiting for service '$ServiceName' to start...")
        while ($service.Status -ne 'Running' -and $Elapsed -lt $WaitTimeoutSeconds) {
            Start-Sleep -Seconds $WaitInterval
            $Elapsed += $WaitInterval
            $service = Get-Service -Name $ServiceName
            Write-Host ("`rWaiting: {0}/{1} seconds..." -f $Elapsed, $WaitTimeoutSeconds) -NoNewline
        }
        Write-Host ""
        if ($service.Status -eq 'Running') {
            Write-OK ("Service '$ServiceName' is now running.")
        } else {
            Write-Err ("Service '$ServiceName' failed to start after $WaitTimeoutSeconds seconds. Current status: $($service.Status)")
        }
    }
} catch {
    Write-Err ("Service '$ServiceName' not found.")
}

# ----------------------------
# 7. Display post-installation login instructions
# ----------------------------
$LoginURL = $CDPURL
$Username = "AOAdmin"
$Password = $Config.AdminPassword

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Installation verification complete." -ForegroundColor Cyan
Write-Host "Before running the next script, please log into the BAO CDP console:" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  Site     : {0}" -f $LoginURL) -ForegroundColor Yellow
Write-Host ("  Username : {0}" -f $Username) -ForegroundColor Yellow
Write-Host ("  Password : {0}" -f $Password) -ForegroundColor Yellow
Write-Host ""
Write-Host "Open the above site in a web browser and verify that you can successfully log in." -ForegroundColor Cyan
Write-Host "Once confirmed, proceed with the next installation or configuration step." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

Write-OK "BAO CDP silent installation script completed."