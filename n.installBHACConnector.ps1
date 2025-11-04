# ------------------------------------------------------------
# Install BMC Helix Server Automation Connector
# ------------------------------------------------------------
# This script:
# 1. Reads C:\Temp\tsas.config for TSAS variables
# 2. Ensures tssa.connector.bmc.com exists in hosts
# 3. Prompts for Helix Demo instance number
# 4. Displays connector information in a neat table
# 5. Opens Automation Console in browser
# 6. Waits for Server Automation Connector zip download
# 7. Extracts and installs the connector
# 8. Starts the service if needed
# ------------------------------------------------------------

# ----------------------------
# Helper function for prompts
# ----------------------------
function Prompt-Required($Message) {
    do {
        $input = Read-Host $Message
        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "[error] You must provide a value." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($input))
    return $input
}

# ----------------------------
# 1. Load configuration
# ----------------------------
$ConfigPath = "C:\Temp\tsas.config"
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[error] Configuration file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

try {
    $Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json -ErrorAction Stop
    Write-Host "[ok] Loaded configuration from $ConfigPath" -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to parse JSON config: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$Hostname      = $Config.Hostname
$AdminUser     = $Config.AdminUser
$AdminPassword = $Config.AdminPassword
$TSASInstallLocation = $Config.TSASInstallLocation

# ----------------------------
# 2. Update hosts file
# ----------------------------
$HostsFile = "$env:windir\system32\drivers\etc\hosts"
$HostsEntry = "$($Config.IPAddress)`ttssa.connector.bmc.com"
$HostsContent = Get-Content $HostsFile -ErrorAction Stop

if ($HostsContent -notcontains $HostsEntry) {
    Write-Host "[info] Adding tssa.connector.bmc.com entry to hosts..." -ForegroundColor Cyan
    try {
        Add-Content -Path $HostsFile -Value $HostsEntry
        Write-Host "[ok] Hosts file updated." -ForegroundColor Green
    } catch {
        Write-Host "[error] Failed to update hosts file: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ok] Hosts entry already exists." -ForegroundColor Green
}

# ----------------------------
# 3. Prompt for Helix Demo Instance
# ----------------------------
$DemoInstance = Prompt-Required "Enter the Helix Demo instance number (XXXX):"

Write-Host ("[info] You entered instance number: " + $DemoInstance) -ForegroundColor Cyan

$DemoInstance = $DemoInstance.Trim()
$DemoUrl = "https://helixdemoash$DemoInstance-itom-demo.onbmc.com/automation-console/#/administration/connectors"

# ----------------------------
# 4. Display connector info table
# ----------------------------
$Table = @(
    [PSCustomObject]@{ Field = "Connector Name"; FieldValue = "Server Automation Connector" },
    [PSCustomObject]@{ Field = "Truesight Server Automation Host Name"; FieldValue = $Hostname },
    [PSCustomObject]@{ Field = "Truesight Server Automation Application Port"; FieldValue = "9843" },
    [PSCustomObject]@{ Field = "Truesight Server Automation Role Name"; FieldValue = "BLAdmins" },
    [PSCustomObject]@{ Field = "User Name"; FieldValue = $AdminUser },
    [PSCustomObject]@{ Field = "Password"; FieldValue = $AdminPassword },
    [PSCustomObject]@{ Field = "Role"; FieldValue = "BLAdmins" },
    [PSCustomObject]@{ Field = "Authentication Method"; FieldValue = "Secure Remote Password" },
    [PSCustomObject]@{ Field = "TSSA Properties"; FieldValue = "" },
    [PSCustomObject]@{ Field = "Collection Mode"; FieldValue = "30 Min" }
)

Write-Host "Please use the following information in the connector creation form:" -ForegroundColor Cyan
$Table | Format-Table -AutoSize

# ----------------------------
# 5. Open Automation Console
# ----------------------------
Write-Host "`n[info] Opening Automation Console in browser..." -ForegroundColor Cyan
Start-Process $DemoUrl

Write-Host "[info] Once the Server Automation Connector zip is downloaded, press the Spacebar to continue..." -ForegroundColor Cyan
do {
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} while ($key.VirtualKeyCode -ne 32)

# ----------------------------
# 6. Locate downloaded zip
# ----------------------------
$UserDownloads = "C:\Users\$env:USERNAME\Downloads"
$ZipFile = Join-Path $UserDownloads "Server Automation Connector.zip"

if (-not (Test-Path $ZipFile)) {
    Write-Host "[error] Could not find $ZipFile" -ForegroundColor Red
    exit 1
} else {
    Write-Host "[ok] Found zip file: $ZipFile" -ForegroundColor Green
}

# ----------------------------
# 7. Extract zip
# ----------------------------
$ExtractDir = Join-Path $TSASInstallLocation "Server Automation Connector"

if (-not (Test-Path $ExtractDir)) {
    New-Item -Path $ExtractDir -ItemType Directory -Force | Out-Null
}

try {
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force
    Write-Host "[ok] Extracted Server Automation Connector to $ExtractDir" -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to extract zip: $_" -ForegroundColor Red
    exit 1
}

# ----------------------------
# 8. Run installer
# ----------------------------
$OriginalDir = Get-Location
Set-Location $ExtractDir

$BsaExe = Join-Path $ExtractDir "bsa-connector.exe"

if (-not (Test-Path $BsaExe)) {
    Write-Host "[error] Could not find bsa-connector.exe in $ExtractDir" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "[info] Running bsa-connector.exe install..." -ForegroundColor Cyan
    Start-Process -FilePath $BsaExe -ArgumentList "install" -Wait -NoNewWindow
    Write-Host "[ok] Server Automation Connector installed." -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to run bsa-connector.exe: $_" -ForegroundColor Red
    exit 1
}

Set-Location $OriginalDir

# ----------------------------
# 9. Check and start service
# ----------------------------
$ServiceName = "bmc-server-automation-connector"

try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        Write-Host "[info] Starting service $ServiceName ..." -ForegroundColor Cyan
        Start-Service -Name $ServiceName
        $svc.WaitForStatus('Running', '00:00:30')
    }
    Write-Host "[ok] Service $ServiceName is running." -ForegroundColor Green
} catch {
    Write-Host "[error] Could not find or start service $ServiceName" -ForegroundColor Red
    exit 1
}

Write-Host "[ok] Server Automation Connector installation complete." -ForegroundColor Green