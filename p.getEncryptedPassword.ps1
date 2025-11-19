<#
.SYNOPSIS
    Guides the user through encrypting the AdminPassword using the PlatformMaintenanceTool.
    Opens the application, waits for manual input, then captures and stores the encrypted password
    back into c:\temp\tsas.config as "EncryptedPassword".
#>

# ----------------------------
# 1. Configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"
$InstallBase = "C:\Temp"
$AppPattern = "windows_bao_server_installer_*_*_*"
$AppSubPath = "files\MaintainBMCAO"
$AppExecutable = "PlatformMaintenanceTool.cmd"

# ----------------------------
# 2. Colour-coded output helpers
# ----------------------------
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrorMsg($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ----------------------------
# 3. Load tsas.config and extract variables
# ----------------------------
if (-not (Test-Path $ConfigFile)) {
    Write-ErrorMsg "Configuration file not found: $ConfigFile"
    exit 1
}

try {
    $Config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
    $AdminPassword = $Config.AdminPassword
    if (-not $AdminPassword) {
        Write-ErrorMsg "AdminPassword not found in tsas.config."
        exit 1
    }
} catch {
    Write-ErrorMsg "Failed to read or parse tsas.config. Please check JSON formatting."
    exit 1
}

# ----------------------------
# 4. Locate the PlatformMaintenanceTool
# ----------------------------
$AppDir = Get-ChildItem -Path $InstallBase -Directory -Filter $AppPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $AppDir) {
    Write-ErrorMsg "Could not find a folder matching $AppPattern in $InstallBase."
    exit 1
}

$FullAppPath = Join-Path $AppDir.FullName $AppSubPath
$CmdPath = Join-Path $FullAppPath $AppExecutable

if (-not (Test-Path $CmdPath)) {
    Write-ErrorMsg "Expected application not found: $CmdPath"
    exit 1
}

# ----------------------------
# 5. Guide the user
# ----------------------------
Write-Info "Please copy the following Admin Password (it will also be placed in your clipboard):"
Write-Host "`n$AdminPassword`n" -ForegroundColor Yellow

Set-Clipboard -Value $AdminPassword
Write-OK "Password copied to clipboard."

Write-Host ""
Write-Info "Next, we will open the Platform Maintenance Tool."
Write-Host "Follow these steps once the application opens:" -ForegroundColor Cyan
Write-Host "  1. Click on the 'Encrypt' tab."
Write-Host "  2. Paste the password (Ctrl+V) into both password boxes."
Write-Host "  3. Change the drop-down box labeled 'Select Encryption Method' to 'Silent Installation Password'."
Write-Host "  4. Click 'Encrypt'."
Write-Host "  5. Copy the resulting encrypted password."
Write-Host "  6. Close the Platform Maintenance Tool."
Write-Host ""
Read-Host "Press ENTER when you are ready to open the application"

# ----------------------------
# 6. Launch the application
# ----------------------------
try {
    Write-Info "Launching PlatformMaintenanceTool..."
    Start-Process -FilePath $CmdPath -WorkingDirectory $FullAppPath
    Write-Host ""
    Read-Host "When the application has been closed, press ENTER to continue"
} catch {
    Write-ErrorMsg "Failed to start PlatformMaintenanceTool."
    exit 1
}

# ----------------------------
# 7. Capture encrypted password from user
# ----------------------------
$EncryptedPassword = Read-Host "Please paste or type the encrypted password shown in the tool"

if (-not $EncryptedPassword) {
    Write-ErrorMsg "No encrypted password entered. Cannot continue."
    exit 1
}

# ----------------------------
# 8. Update tsas.config with EncryptedPassword
# ----------------------------
try {
    $Config | Add-Member -NotePropertyName "EncryptedPassword" -NotePropertyValue $EncryptedPassword -Force
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Force -Encoding UTF8
    Write-OK "Encrypted password saved to tsas.config."
    Write-Host "Path: $ConfigFile" -ForegroundColor Cyan
} catch {
    Write-ErrorMsg "Failed to update tsas.config. Please check file permissions."
    exit 1
}

Write-OK "Process complete. The encrypted password is now stored for later use."

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
