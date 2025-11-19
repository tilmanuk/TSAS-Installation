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
    Write-Host "[OK] Verified write access to $TempDir" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 2. Download the installer
# ----------------------------
if (-not (Test-Path $InstallerPath)) {
    Write-Host "[INFO] Downloading Visual C++ Redistributable installer..." -ForegroundColor Cyan
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
# 3. Install the EXE silently
# ----------------------------
if (Test-Path $InstallerPath) {
    Write-Host "[INFO] Installing Visual C++ Redistributable silently..." -ForegroundColor Cyan
    $Arguments = "/install /quiet /norestart"

    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] Visual C++ Redistributable installed successfully." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] Installation failed. Exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
} else {
    Write-Error "[ERROR] Installer file not found at $InstallerPath."
    exit 1
}

Write-Host "[OK] All done." -ForegroundColor Green

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
