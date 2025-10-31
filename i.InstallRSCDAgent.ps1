# i.InstallRSCDAgent.ps1
# Silently installs the BMC RSCD Agent using parameters from C:\Temp\tsas.config
# Automatically detects RSCD installer name (e.g., RSCD216-WIN64.msi)
# Ensures service running and updates C:\Windows\rsc\exports idempotently

# ----------------------------
# 1. Ensure C:\Temp writable
# ----------------------------
$TempDir = "C:\Temp"
Write-Host "Checking $TempDir folder..."
if (-not (Test-Path $TempDir)) {
    Write-Host "Creating $TempDir ..."
    New-Item -Path $TempDir -ItemType Directory | Out-Null
}

try {
    $TestFile = Join-Path $TempDir "write_test.tmp"
    "test" | Out-File -FilePath $TestFile -ErrorAction Stop
    Remove-Item $TestFile -Force
    Write-Host "[OK] Verified write access to $TempDir"
} catch {
    Write-Error "[ERROR] Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 2. Locate installer automatically
# ----------------------------
$InstallerPath = 'C:\Temp\rscd\windows_64'
if (-not (Test-Path $InstallerPath)) {
    Write-Error "[ERROR] Folder not found: $InstallerPath. Please extract RSCD installer to this location."
    exit 1
}

$InstallerFiles = Get-ChildItem -Path $InstallerPath -Filter 'RSCD*-WIN64.msi' -File -ErrorAction SilentlyContinue
if (-not $InstallerFiles) {
    Write-Error "[ERROR] No RSCD*-WIN64.msi file found in $InstallerPath."
    exit 1
}

if ($InstallerFiles.Count -gt 1) {
    Write-Warning "[WARN] Multiple RSCD installers found:"
    $InstallerFiles | ForEach-Object { Write-Host " - $($_.Name)" }
    $Selected = Read-Host "Enter the exact file name you want to use (or press Enter to use the first one)"
    if ([string]::IsNullOrWhiteSpace($Selected)) {
        $InstallerExe = $InstallerFiles[0].FullName
    } else {
        $SelectedFile = Join-Path $InstallerPath $Selected
        if (-not (Test-Path $SelectedFile)) {
            Write-Error "[ERROR] File not found: $SelectedFile"
            exit 1
        }
        $InstallerExe = $SelectedFile
    }
} else {
    $InstallerExe = $InstallerFiles[0].FullName
}

Write-Host "[OK] Found RSCD installer: $InstallerExe"

# ----------------------------
# 3. Load tsas.config (JSON)
# ----------------------------
$ConfigFile = 'C:\Temp\tsas.config'
if (-not (Test-Path $ConfigFile)) {
    Write-Error "[ERROR] Configuration file not found: $ConfigFile"
    exit 1
}

try {
    $Config = Get-Content -Raw -Path $ConfigFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "[ERROR] Failed to read/parse tsas.config: $($_.Exception.Message)"
    exit 1
}

$RSCDUser    = $Config.RSCDUser
$InstallRoot = $Config.TSASInstallLocation
$InstallRoot = Join-Path $InstallRoot "RSCD"

if ([string]::IsNullOrWhiteSpace($InstallRoot) -or [string]::IsNullOrWhiteSpace($RSCDUser)) {
    Write-Error "[ERROR] Missing TSASInstallLocation or RSCDUser in tsas.config."
    exit 1
}

$RSCDInstallPath = Join-Path $InstallRoot 'RSCD'
$LogFile = Join-Path $TempDir 'RSCDInstall.log'

Write-Host "[INFO] Installing RSCD Agent to: $RSCDInstallPath"
Write-Host "[INFO] Log file: $LogFile"

# ----------------------------
# 4. Run the RSCD Agent Installer (MSI)
# ----------------------------
Write-Host "[INFO] Installing RSCD Agent silently..."

$InstallerFile = Get-ChildItem -Path "C:\Temp\rscd\windows_64" -Filter "RSCD*-WIN64.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $InstallerFile) {
    Write-Error "[ERROR] Could not find RSCD*-WIN64.msi in C:\Temp\rscd\windows_64"
    exit 1
}

$InstallerPath = $InstallerFile.FullName
Write-Host "[OK] Found installer: $InstallerPath"

$Arguments = "/i `"$InstallerPath`" /qn /norestart INSTALLDIR=`"$InstallRoot`""

try {
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] RSCD Agent installed successfully."
    } else {
        Write-Error "[ERROR] RSCD installation failed with exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
} catch {
    Write-Error "[ERROR] RSCD installation failed: $_"
    exit 1
}

# ----------------------------
# 5. Check RSCD Agent Service is running
# ----------------------------
$ServiceName = "TrueSight Server Automation RSCD Agent"
try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        Write-Host "[INFO] Starting service $ServiceName ..."
        Start-Service -Name $ServiceName
        $svc.WaitForStatus('Running', '00:00:30')  # 30 seconds timeout
    }
    Write-Host "[OK] RSCD Agent service '$ServiceName' is running."
} catch {
    Write-Error "[ERROR] Could not find or start service '$ServiceName'. $_"
    exit 1
}

# ----------------------------
# 6. Update exports file (idempotent)
# ----------------------------
$ExportsFile = 'C:\Windows\rsc\exports'
if (-not (Test-Path $ExportsFile)) {
    Write-Warning "[WARN] Exports file not found. Creating: $ExportsFile"
    try {
        New-Item -Path $ExportsFile -ItemType File -Force | Out-Null
    } catch {
        Write-Error "[ERROR] Failed to create exports file: $($_.Exception.Message)"
        exit 1
    }
}

try {
    $lines = Get-Content -Path $ExportsFile -ErrorAction Stop
    $escapedUser = [regex]::Escape($RSCDUser)
    $pattern = "^\*\s+rw,\s*user=$escapedUser\s*$"

    if ($lines -match $pattern) {
        Write-Host "[OK] Exports file already contains entry for user $RSCDUser."
    } else {
        $NewLine = "*`trw, user=$RSCDUser"
        Add-Content -Path $ExportsFile -Value $NewLine -ErrorAction Stop
        Write-Host "[OK] Added new exports entry: $NewLine"
    }
} catch {
    Write-Error "[ERROR] Failed to update exports file: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "[OK] RSCD Agent installation and configuration complete."
Write-Host "    Install path: $RSCDInstallPath"
Write-Host "    Exports entry verified for: $RSCDUser"
