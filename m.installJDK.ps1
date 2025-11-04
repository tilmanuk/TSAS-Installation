<#
.SYNOPSIS
    Downloads and installs Microsoft JDK 17 silently.
#>

# ----------------------------
# Configuration
# ----------------------------
$DownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-17.0.17-windows-x64.msi"
$TempDir = "C:\Temp"
$InstallerPath = Join-Path $TempDir "microsoft-jdk-17.0.17-windows-x64.msi"
$LogFile = Join-Path $TempDir "jdk17_install.log"

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
# ----------------------------
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
# 2. Download the installer
# ----------------------------
if (-not (Test-Path $InstallerPath)) {
    Write-Host "[INFO] Downloading Microsoft JDK 17 installer..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Download complete: $InstallerPath" -ForegroundColor Green
    } catch {
        Write-Error "[ERROR] Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "[INFO] Using existing installer: $InstallerPath" -ForegroundColor Cyan
}

# ----------------------------
# 3. Install the MSI silently
# ----------------------------
if (Test-Path $InstallerPath) {
    Write-Host "[INFO] Installing Microsoft JDK 17 silently..." -ForegroundColor Cyan

    # MSI arguments: silent install, no restart, logging enabled
    $Arguments = "/i `"$InstallerPath`" /qn /norestart /log `"$LogFile`""

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] Microsoft JDK 17 installation completed successfully." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] JDK installation failed. Exit code: $($process.ExitCode). Check log: $LogFile"
        exit $process.ExitCode
    }
} else {
    Write-Error "[ERROR] Installer file not found at $InstallerPath."
    exit 1
}

Write-Host "[OK] All done. Log file: $LogFile" -ForegroundColor Green