<#
.SYNOPSIS
    Downloads and installs Microsoft ODBC Driver for SQL Server silently (with license acceptance).
#>

# ----------------------------
# Configuration
# ----------------------------
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2266337"
$TempDir = "C:\Temp"
$InstallerPath = Join-Path $TempDir "msodbcsql.msi"
$LogFile = Join-Path $TempDir "msodbcsql_Install.log"

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
# ----------------------------
Write-Host "Checking C:\Temp folder..."
if (-not (Test-Path $TempDir)) {
    Write-Host "Creating $TempDir ..."
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
    Write-Host "[INFO] Downloading ODBC driver installer from Microsoft..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Download complete: $InstallerPath" -ForegroundColor Green
    } catch {
        Write-Error "[ERROR] Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "[INFO] Using existing file: $InstallerPath" -ForegroundColor Cyan
}

# ----------------------------
# 3. Install the MSI silently
# ----------------------------
if (Test-Path $InstallerPath) {
    Write-Host "[INFO] Installing ODBC Driver silently..." -ForegroundColor Cyan
    
    # Added required license acceptance property
    $Arguments = "/i `"$InstallerPath`" /qn /norestart /log `"$LogFile`" IACCEPTMSODBCSQLLICENSETERMS=YES"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] ODBC Driver installation completed successfully." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] ODBC Driver installation failed. Exit code: $($process.ExitCode). Check log: $LogFile"
        exit $process.ExitCode
    }
} else {
    Write-Error "[ERROR] Installer file not found at $InstallerPath."
    exit 1
}

Write-Host "[OK] All done. Log file: $LogFile" -ForegroundColor Green
