<#
.SYNOPSIS
    Checks for RSCD and TSSA installer ZIPs in C:\Temp, extracts them if present,
    otherwise opens the BMC Support page for download instructions.
#>

# ----------------------------
# 1. Configuration
# ----------------------------
$TempDir = "C:\Temp"
$RSCDPattern = "TSSA???-RSCDAgents.zip"
$TSSAPattern = "TSSA???-WIN64.zip"
$BmcSupportUrl = "https://support.bmc.com"

# ----------------------------
# 2. Ensure C:\Temp exists and is writable
# ----------------------------
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
# 3. Look for the installer ZIP files
# ----------------------------
Write-Host "Searching for installer ZIP files in $TempDir..."
$RSCDFile = Get-ChildItem -Path $TempDir -Filter $RSCDPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$TSSAFile = Get-ChildItem -Path $TempDir -Filter $TSSAPattern -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $RSCDFile -or -not $TSSAFile) {
    Write-Warning "[WARN] Required files not found in $TempDir."
    if (-not $RSCDFile) { Write-Host "Missing: file matching pattern '$RSCDPattern'" }
    if (-not $TSSAFile) { Write-Host "Missing: file matching pattern '$TSSAPattern'" }
    Write-Host ""
    Write-Host "Please download the RSCD Agent and TrueSight Server Automation installers from BMC Support:"
    Write-Host $BmcSupportUrl -ForegroundColor Cyan
    Start-Process $BmcSupportUrl
    exit 1
}

Write-Host "[OK] Found RSCD ZIP: $($RSCDFile.Name)"
Write-Host "[OK] Found TSSA ZIP: $($TSSAFile.Name)"

# ----------------------------
# 4. Extract ZIP files
# ----------------------------
try {
    Write-Host "Extracting $($RSCDFile.Name)..."
    Expand-Archive -Path $RSCDFile.FullName -DestinationPath $TempDir -Force -ErrorAction Stop
    Write-Host "[OK] Extracted RSCD Agent."

    Write-Host "Extracting $($TSSAFile.Name)..."
    Expand-Archive -Path $TSSAFile.FullName -DestinationPath $TempDir -Force -ErrorAction Stop
    Write-Host "[OK] Extracted TSSA WIN64."
} catch {
    Write-Error "[ERROR] Extraction failed: $($_.Exception.Message)"
    exit 1
}

Write-Host "[OK] Extraction complete. Files are ready in $TempDir."
