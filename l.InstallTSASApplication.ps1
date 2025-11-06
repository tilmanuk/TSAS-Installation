<#
.SYNOPSIS
    Prepares and launches the TSSA installer interactively with database connection details.
    After installation, checks that the 'BladeApp Server' service is running.
#>

# ----------------------------
# 1. Locate TSSA installer
# ----------------------------
# ----------------------------
# Locate AppServer installer folder
# ----------------------------
$BaseDir = "C:\Temp"

# Locate the extracted TSSA???-WIN64 folder
$ExtractedDir = Get-ChildItem -Path $BaseDir -Directory -Filter "TSSA???-WIN64" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $ExtractedDir) {
    Write-Host "[ERROR] Could not locate extracted folder matching TSSA???-WIN64 in $BaseDir" -ForegroundColor Red
    Write-Host "[INFO] Please extract the TSAA installer ZIP to $BaseDir" -ForegroundColor Cyan
    exit 1
}

# Construct the full path to the AppServer installer folder
$InstallerFolder = Join-Path $ExtractedDir.FullName "Disk1\files\installers\appserver_64"

if (-not (Test-Path $InstallerFolder)) {
    Write-Host "[ERROR] AppServer installer folder not found: $InstallerFolder" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] AppServer installer folder located at: $InstallerFolder" -ForegroundColor Green
$InstallerPattern = "TSSA???-WIN64.exe"

$Installer = Get-ChildItem -Path $InstallerFolder -Filter $InstallerPattern | Select-Object -First 1

if (-not $Installer) {
    Write-Error "[ERROR] Could not find installer matching '$InstallerPattern' in $InstallerFolder"
    Write-Host "Please download the TSSA installer from support.bmc.com"
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

Write-Host "[OK] Found installer: $($Installer.FullName)" -ForegroundColor Green

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
    Write-Host "[INFO] Launching TSSA installer: $($Installer.FullName)" -ForegroundColor Cyan
    Start-Process -FilePath $Installer.FullName -Wait
    Write-Host "[OK] Installer process completed." -ForegroundColor Green
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
        Write-Host "[WARN] Service '$ServiceName' is not running. Attempting to start..." -ForegroundColor Red

        # Start service silently (suppress default "Waiting..." output)
        Start-Service -Name $ServiceName -ErrorAction Stop | Out-Null

        # Show our own progress indicator
        $spinner = @("|","/","-","\")
        $i = 0
        $timeout = (Get-Date).AddSeconds(60)
        Write-Host -NoNewline "[INFO] Waiting for service to start " -ForegroundColor Cyan

        while ((Get-Service -Name $ServiceName).Status -ne 'Running' -and (Get-Date) -lt $timeout) {
            Write-Host -NoNewline ("`b" + $spinner[$i % $spinner.Length])
            Start-Sleep -Milliseconds 250
            $i++
        }

        # Clear spinner and finish line
        Write-Host "`b "

        if ((Get-Service -Name $ServiceName).Status -eq 'Running') {
            Write-Host "[OK] Service '$ServiceName' started successfully." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Service '$ServiceName' did not start within the expected time." -ForegroundColor Red
        }

    } else {
        Write-Host "[OK] Service '$ServiceName' is already running." -ForegroundColor Green
    }
} catch {
    Write-Error "[ERROR] Could not find service '$ServiceName' or start it: $($_.Exception.Message)"
}

# ----------------------------
# 7. Guidance for post-install login
# ----------------------------
Write-Host ""
Write-Host "[INFO] If everything is up and running, but you cannot log in:" -ForegroundColor Cyan
Write-Host "       1. Type 'nsh' in the command prompt."
Write-Host "       2. Run 'blasadmin' and wait for it to finish."
Write-Host ""
