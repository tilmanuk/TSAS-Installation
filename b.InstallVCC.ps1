<#
.SYNOPSIS
    Downloads and installs Microsoft Visual C++ Redistributable (x64) silently.
#>

# ----------------------------
# Configuration
# ----------------------------
$DownloadUrl = "https://aka.ms/vs/15/release/vc_redist.x64.exe"
$TempDir = "C:\Temp"
$InstallerPath = Join-Path $TempDir "vc_redist.x64.exe"

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
    Write-Host "[OK] Verified write access to $TempDir"
} catch {
    Write-Error "[ERROR] Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 2. Download the installer
# ----------------------------
if (-not (Test-Path $InstallerPath)) {
    Write-Host "[INFO] Downloading Visual C++ Redistributable installer..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Download complete: $InstallerPath"
    } catch {
        Write-Error "[ERROR] Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "[INFO] Using existing file: $InstallerPath"
}

# ----------------------------
# 3. Install the EXE silently
# ----------------------------
if (Test-Path $InstallerPath) {
    Write-Host "[INFO] Installing Visual C++ Redistributable silently..."
    $Arguments = "/install /quiet /norestart"

    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] Visual C++ Redistributable installed successfully."
    } else {
        Write-Error "[ERROR] Installation failed. Exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
} else {
    Write-Error "[ERROR] Installer file not found at $InstallerPath."
    exit 1
}

Write-Host "[OK] All done."
