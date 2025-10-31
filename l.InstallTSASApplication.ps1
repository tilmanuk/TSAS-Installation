<#
.SYNOPSIS
    Prepares and launches the TSSA installer interactively with database connection details.
    After installation, checks that the 'BladeApp Server' service is running.
#>

# ----------------------------
# 1. Locate TSSA installer
# ----------------------------
$InstallerFolder = "C:\Temp\Disk1\files\installers\appserver_64"
$InstallerPattern = "TSSA???-WIN64.exe"

$Installer = Get-ChildItem -Path $InstallerFolder -Filter $InstallerPattern | Select-Object -First 1

if (-not $Installer) {
    Write-Error "[ERROR] Could not find installer matching '$InstallerPattern' in $InstallerFolder"
    Write-Host "Please download the TSSA installer from support.bmc.com"
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

Write-Host "[OK] Found installer: $($Installer.FullName)"

# ----------------------------
# 2. Load JSON configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"

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

$Hostname      = $Config.Hostname
$SQLInstance   = $Config.SQLInstance
$SQLDBName     = $Config.SQLDBName
$AdminUser     = $Config.AdminUser
$AdminPassword = $Config.AdminPassword

# ----------------------------
# 3. Print database connection details
# ----------------------------
Write-Host ""
Write-Host "==================== DATABASE CONNECTION DETAILS ====================" -ForegroundColor Cyan
Write-Host "DB Instance:       $Hostname\$SQLInstance"
Write-Host "DB Name:           $SQLDBName"
Write-Host "DB User:           $AdminUser"
Write-Host "DB User Password:  $AdminPassword"
Write-Host ""
Write-Host "Password to use for 'bladmin' and 'rbacadmin': $AdminPassword"
Write-Host "===================================================================="
Write-Host ""

# ----------------------------
# 4. Pause for user review
# ----------------------------
Write-Host "Press any key to continue and launch the TSSA installer..."
[void][System.Console]::ReadKey($true)
Write-Host ""

# ----------------------------
# 5. Launch TSSA installer interactively
# ----------------------------
try {
    Write-Host "[INFO] Launching TSSA installer: $($Installer.FullName)"
    Start-Process -FilePath $Installer.FullName -Wait
    Write-Host "[OK] Installer process completed."
} catch {
    Write-Error "[ERROR] Failed to launch TSSA installer: $($_.Exception.Message)"
    exit 1
}

<#
.SYNOPSIS
    Prepares and launches the TSSA installer interactively with database connection details.
    After installation, checks that the 'BladeApp Server' service is running.
#>

# ----------------------------
# 1. Locate TSSA installer
# ----------------------------
$InstallerFolder = "C:\Temp\Disk1\files\installers\appserver_64"
$InstallerPattern = "TSSA???-WIN64.exe"

$Installer = Get-ChildItem -Path $InstallerFolder -Filter $InstallerPattern | Select-Object -First 1

if (-not $Installer) {
    Write-Error "[ERROR] Could not find installer matching '$InstallerPattern' in $InstallerFolder"
    Write-Host "Please download the TSSA installer from support.bmc.com"
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

Write-Host "[OK] Found installer: $($Installer.FullName)"

# ----------------------------
# 2. Load JSON configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"

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

$Hostname      = $Config.Hostname
$SQLInstance   = $Config.SQLInstance
$SQLDBName     = $Config.SQLDBName
$AdminUser     = $Config.AdminUser
$AdminPassword = $Config.AdminPassword

# ----------------------------
# 3. Print database connection details
# ----------------------------
Write-Host ""
Write-Host "==================== DATABASE CONNECTION DETAILS ====================" -ForegroundColor Cyan
Write-Host "DB Instance:       $Hostname\$SQLInstance"
Write-Host "DB Name:           $SQLDBName"
Write-Host "DB User:           $AdminUser"
Write-Host "DB User Password:  $AdminPassword"
Write-Host ""
Write-Host "Password to use for 'bladmin' and 'rbacadmin': $AdminPassword"
Write-Host "===================================================================="
Write-Host ""

# ----------------------------
# 4. Pause for user review
# ----------------------------
Write-Host "Press any key to continue and launch the TSSA installer..."
[void][System.Console]::ReadKey($true)
Write-Host ""

# ----------------------------
# 5. Launch TSSA installer interactively
# ----------------------------
try {
    Write-Host "[INFO] Launching TSSA installer: $($Installer.FullName)"
    Start-Process -FilePath $Installer.FullName -Wait
    Write-Host "[OK] Installer process completed."
} catch {
    Write-Error "[ERROR] Failed to launch TSSA installer: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# 6. Check BladeApp Server service
# ----------------------------
$ServiceName = "BladeApp Server"

try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop

    if ($svc.Status -ne 'Running') {
        Write-Host "[WARN] Service '$ServiceName' is not running. Attempting to start..."
        Start-Service -Name $ServiceName -ErrorAction Stop
        Write-Host "[OK] Service '$ServiceName' started successfully."
    } else {
        Write-Host "[OK] Service '$ServiceName' is already running."
    }
} catch {
    Write-Error "[ERROR] Could not find service '$ServiceName' or start it: $($_.Exception.Message)"
}

# ----------------------------
# 7. Guidance for post-install login
# ----------------------------
Write-Host ""
Write-Host "[INFO] If everything is up and running, but you cannot log in:"
Write-Host "       1. Type 'nsh' in the command prompt."
Write-Host "       2. Run 'blasadmin' and wait for it to finish."
Write-Host ""

# ----------------------------
# 7. Guidance for post-install login
# ----------------------------
Write-Host ""
Write-Host "[INFO] If everything is up and running, but you cannot log in:"
Write-Host "       1. Type 'nsh' in the command prompt."
Write-Host "       2. Run 'blasadmin' and wait for it to finish."
Write-Host ""
