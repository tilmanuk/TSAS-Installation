<#
.SYNOPSIS
    Create bao-content.ssi from c:\temp\tsas.config and run BAO Content silent installer.
    Based on the BAO CDP installer script.
#>

# ----------------------------
# Configuration
# ----------------------------
$TempDir         = "C:\Temp"
$ConfigFile      = Join-Path $TempDir "tsas.config"
$SilentFile      = Join-Path $TempDir "bao-content.ssi"
$InstallerPrefix = "windows_bao_content_installer_"
$InstallLog      = Join-Path $TempDir "bao-content-install.log"

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

$Hostname       = ToStringSafe $Config.Hostname
$IPAddress      = ToStringSafe $Config.IPAddress
$AdminUser      = ToStringSafe $Config.AdminUser
$AdminPassword  = ToStringSafe $Config.AdminPassword
$Domain         = ToStringSafe $Config.Domain

# Build FQDN properly
$FQDN = $Hostname + "." + $Domain

Write-Info ("Loaded configuration from {0}" -f (ToStringSafe $ConfigFile))
Write-Info ("  Hostname  : {0}" -f $Hostname)
Write-Info ("  Domain    : {0}" -f $Domain)
Write-Info ("  FQDN      : {0}" -f $FQDN)
Write-Info ("  AdminUser : {0}" -f $AdminUser)

# ----------------------------
# 3. Create bao-content.ssi
# ----------------------------
if (Test-Path $SilentFile) {
    Write-Warn ("Existing {0} found. Removing..." -f (ToStringSafe $SilentFile))
    Remove-Item $SilentFile -Force -ErrorAction SilentlyContinue
}

Write-Info ("Generating silent install file: {0}" -f (ToStringSafe $SilentFile))

$ssiContent = @"
-P installLocation=C:\Program Files\BMC Software\AO\Content
-J AO_INSTALLING_FEATURES=BMC-SA-ITSM_Automation,BMC-SA-ITSM_Configuration,AO-AD-VitalQIP,AutoPilot-AD-Utilities,AutoPilot-OA-BAOGridManagement,AutoPilot-OA-Applications_Utilities,AutoPilot-OA-Common_Utilities,AutoPilot-OA-Errors,AutoPilot-OA-Directory_Services_Utilities,AutoPilot-OA-DNS_Integration,AutoPilot-OA-File_Utilities,AutoPilot-OA-Network_Utilities,AutoPilot-OA-Operating_System_Utilities,AutoPilot-OA-Physical_Device_Utilities,AutoPilot-OA-ITSM_Automation,AutoPilot-OA-Event_Orchestration,BMC-AD-Remedy_REST,adapter-rest,adapter-ws
-J AO_REPOSITORY_PROTOCOL=https
-J AO_REPOSITORY_HOST=$FQDN
-J AO_REPOSITORY_PORT=28080
-J AO_REPOSITORY_USER_NAME=aoadmin
-J AO_REPOSITORY_PASSWORD=$AdminPassword
-J AO_CONTENT_INSTALL_TYPE=INSTALL_TYPE_CUSTOM
-J INSTALL_REMEDY_ITSM_INTEGRATIONS=false
-J REMEDY_PORT_NUMBER=
-J REMEDY_USER_NAME=orchestrationuser
-J REMEDY_HOSTNAME=
-J ITSM_AUTHORING_COMPANY=
-J ITSM_AUTHORING_ORGANIZATION=
-J ITSM_AUTHORING_GROUP=
"@

try {
    $ssiContent | Out-File -FilePath $SilentFile -Encoding ASCII -Force
    Write-OK ("Created bao-content.ssi at {0}" -f (ToStringSafe $SilentFile))
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
$SetupCmd = Join-Path $InstallerDirPath "Content\Disk1\setup.cmd"

if (-not (Test-Path $SetupCmd)) {
    Write-Err ("Installer executable not found: {0}" -f $SetupCmd)
    exit 1
}

Write-OK ("Installer found at: {0}" -f $SetupCmd)

# ----------------------------
# 5. Run BAO Content Installer
# ----------------------------
$OptionsFile = $SilentFile
$CmdLine = "`"$SetupCmd`" -i silent -DOPTIONS_FILE=`"$OptionsFile`""

Write-Info "About to run silent installation command:"
Write-Host "       $CmdLine" -ForegroundColor Yellow

Start-Process -FilePath $SetupCmd -ArgumentList "-i silent -DOPTIONS_FILE=`"$OptionsFile`"" -Wait

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
    Write-OK "BAO Content installation completed successfully."
} else {
    Write-Err ("Installation finished with exit code $LASTEXITCODE. See log: $InstallLog")
}

# ----------------------------
# 6. Check BAO-REPO service
# ----------------------------
$ServiceName = "BAO-REPO"
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
# 7. Post-installation instructions
# ----------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "BAO Content installation completed successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Please now log into the BAO CDP console and perform the following configuration steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Log into the CDP Web Console using a browser:" -ForegroundColor Yellow
Write-Host ("   Site     : https://" + $FQDN + ":38080/baocdp") -ForegroundColor White
Write-Host "   Username : AOAdmin" -ForegroundColor White
Write-Host ("   Password : " + $Config.AdminPassword) -ForegroundColor White
Write-Host ""
Write-Host "2. Once logged in, navigate to the Manage tab > Adapters." -ForegroundColor Yellow
Write-Host "3. Locate the adapter named 'ro-adapter-ws' and tick the checkbox next to it." -ForegroundColor Yellow
Write-Host "4. Click the 'Add to Grid' button which will now become available." -ForegroundColor Yellow
Write-Host ""
Write-Host "5. In the adapter that appears on the right side panel, click the 'Configure' button." -ForegroundColor Yellow
Write-Host "6. In the configuration screen, enter the following:" -ForegroundColor Yellow
Write-Host "     Name: WebServiceAdapter" -ForegroundColor White
Write-Host "   Then scroll down and click OK." -ForegroundColor White
Write-Host ""
Write-Host "7. Go to the 'Modules' tab." -ForegroundColor Yellow
Write-Host "8. Tick all modules listed in the left-hand grid, then click 'Activate'." -ForegroundColor Yellow
Write-Host "   The modules will now appear in the right-hand pane." -ForegroundColor White
Write-Host ""
Write-Host "9. Click the module named 'BMC-SA-ITSM_Configuration'." -ForegroundColor Yellow
Write-Host "10. Expand the tree: Configuration > ITSM > BMC Helix_AR_System > User Defaults." -ForegroundColor Yellow
Write-Host ""
Write-Host "11. Update the following fields using Helix ITSM credentials:" -ForegroundColor Yellow
Write-Host "     ARUser      : <Helix user with Change Admin privileges>" -ForegroundColor White
Write-Host "     ARPassword  : <corresponding password>" -ForegroundColor White
Write-Host "     ARUrl       : https://helixdemoashXXXX-demo.onbmc.com/arsys/services/ARService?server=onbmc-s" -ForegroundColor White
Write-Host ""
Write-Host "12. Once all values are entered, click 'OK' to save the configuration." -ForegroundColor Yellow
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-OK "BAO Content installation script completed."