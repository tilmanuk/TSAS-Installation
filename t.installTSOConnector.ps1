# ------------------------------------------------------------
# Install BMC Helix Server Automation Connector
# ------------------------------------------------------------
# This script:
# 1. Reads C:\Temp\tsas.config for TSAS variables
# 2. Ensures tssa.connector.bmc.com exists in hosts
# 3. Prompts for Helix Demo instance number
# 4. Displays connector information in a neat table
# 5. Opens Automation Console in browser
# 6. Waits for Orchestrator zip download
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
$Domain   = $Config.Domain
$AdminUser     = $Config.AdminUser
$AdminPassword = $Config.AdminPassword
$TSASInstallLocation = $Config.TSASInstallLocation
$HelixURL = $Config.HelixURL
$TSOConnString = "https://$Hostname.$Domain"

# ----------------------------
# 3. Load Helix URL from config
# ----------------------------
if (-not $HelixURL) {
    Write-Host "[error] HelixURL is missing in $ConfigPath" -ForegroundColor Red
    exit 1
}

$DemoUrl = $HelixURL

Write-Host "[info] Using Helix URL from configuration:" -ForegroundColor Cyan
Write-Host "       $DemoUrl" -ForegroundColor Green

# ----------------------------
# 4. Display connector info table
# ----------------------------
$Table = @(
    [PSCustomObject]@{ Field = "Connector Name"; FieldValue = "Orchestration Connector" },
    [PSCustomObject]@{ Field = "Truesight Orchestration Connector Connection String"; FieldValue = $TSOConnString },
    [PSCustomObject]@{ Field = "Truesight Orchestration Connector Port"; FieldValue = "38080" },
    [PSCustomObject]@{ Field = "Truesight Orchestration Connector User Name"; FieldValue = "aoadmin" },
    [PSCustomObject]@{ Field = "Truesight Orchestration Connector Password"; FieldValue = $AdminPassword },
    [PSCustomObject]@{ Field = "Truesight Orchestration Connector Grid Name"; FieldValue = "mygrid" }
)

Write-Host "Please use the following information in the connector creation form:" -ForegroundColor Cyan
$Table | Format-Table -AutoSize

# ----------------------------
# 5. Open Automation Console
# ----------------------------
Write-Host "`n[info] Opening Automation Console in browser..." -ForegroundColor Cyan
Start-Process $DemoUrl

Write-Host "[info] Once the Orchestration Connector zip is downloaded, press the Spacebar to continue..." -ForegroundColor Cyan
do {
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} while ($key.VirtualKeyCode -ne 32)

# ----------------------------
# 6. Locate downloaded zip
# ----------------------------
$UserDownloads = "C:\Users\$env:USERNAME\Downloads"
$ZipFile = Join-Path $UserDownloads "Orchestration Connector.zip"

if (-not (Test-Path $ZipFile)) {
    Write-Host "[error] Could not find $ZipFile" -ForegroundColor Red
    exit 1
} else {
    Write-Host "[ok] Found zip file: $ZipFile" -ForegroundColor Green
}

# ----------------------------
# 7. Extract zip
# ----------------------------
$ExtractDir = Join-Path $TSASInstallLocation "Orchestration Connector"

if (-not (Test-Path $ExtractDir)) {
    New-Item -Path $ExtractDir -ItemType Directory -Force | Out-Null
}

try {
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force
    Write-Host "[ok] Extracted Orchestration Connector to $ExtractDir" -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to extract zip: $_" -ForegroundColor Red
    exit 1
}

# ----------------------------
# 7.1 Update server port in application.properties
# ----------------------------
$AppProperties = Join-Path $ExtractDir "config\application.properties"

Write-Host "[info] Checking for application.properties file..." -ForegroundColor Cyan
if (Test-Path $AppProperties) {
    try {
        Write-Host "[info] Found application.properties. Checking for 'server.port' setting..." -ForegroundColor Cyan
        $FileContent = Get-Content $AppProperties

        if ($FileContent -match 'server\.port=28080') {
            Write-Host "[info] Updating server port from 28080 to 28443..." -ForegroundColor Cyan
            (Get-Content $AppProperties) -replace 'server\.port=28080', 'server.port=28443' |
                Set-Content $AppProperties -Encoding UTF8
            Write-Host "[ok] Port successfully updated to 80443 in application.properties." -ForegroundColor Green
        } else {
            Write-Host "[info] No 'server.port=28080' entry found. No change needed." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[error] Failed to update server port in application.properties." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[error] application.properties not found at expected location: $AppProperties" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Reloading system environment variables..." -ForegroundColor Cyan

# Get system environment variables from registry
$systemEnv = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
$userEnv   = Get-ItemProperty -Path "HKCU:\Environment" -ErrorAction SilentlyContinue

# Merge PATH from system + user scopes (user takes precedence)
$newPath = "$($systemEnv.Path);$($userEnv.Path)"
$env:PATH = $newPath

Write-Host "[OK] PATH variable reloaded into current session." -ForegroundColor Green

# Optional sanity check
Write-Host "[INFO] Java version check..." -ForegroundColor Cyan
try {
    & java -version
} catch {
    Write-Host "[ERROR] Java still not detected in PATH. Please verify installation." -ForegroundColor Red
}

# ----------------------------
# 8. Run installer
# ----------------------------
$OriginalDir = Get-Location
Set-Location $ExtractDir

$BsaExe = Join-Path $ExtractDir "install.bat"

if (-not (Test-Path $BsaExe)) {
    Write-Host "[error] Could not find install.bat in $ExtractDir" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "[info] Running install.bat..." -ForegroundColor Cyan

$Cmd = "cmd.exe"
$Args = "/c `"`"$BsaExe`"`""

Write-Host "       $Cmd $Args" -ForegroundColor Yellow

# Run it inside a command shell and wait for it to finish
$process = Start-Process -FilePath $Cmd -ArgumentList $Args -Wait -NoNewWindow -PassThru


# Check exit code after the process finishes
if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1) {
    Write-Host "[OK] Installation completed successfully." -ForegroundColor Green
} else {
    Write-Host ("[ERROR] Installation exited with code {0}" -f $process.ExitCode) -ForegroundColor Red
}
    Write-Host "[ok] Orchestration Connector installed." -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to run install.bat: $_" -ForegroundColor Red
    exit 1
}

Set-Location $OriginalDir

# ----------------------------
# 9. Check and start service
# ----------------------------
$ServiceName = "tso-connector"

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

Write-Host "[ok] Orchestration Connector installation complete." -ForegroundColor Green

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
