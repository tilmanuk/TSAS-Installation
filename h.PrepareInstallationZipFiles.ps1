<#
.SYNOPSIS
    Checks for RSCD, TSSA, and BAO installer ZIPs in C:\Temp.
    If missing, looks in Downloads and moves them.
    Only if all are missing, opens BMC Support site.
    Skips extraction if already completed.
#>

# ----------------------------
# 1. Configuration
# ----------------------------
$TempDir = "C:\Temp"
$DownloadsDir = Join-Path $env:USERPROFILE "Downloads"
$RSCDPattern = "TSSA???-RSCDAgents.zip"
$TSSAPattern = "TSSA???-WIN64.zip"
$BAOPattern  = "windows_bao_server_installer_??_?_??.zip"
$BmcSupportUrl = "https://support.bmc.com"

# ----------------------------
# 2. Ensure C:\Temp exists and is writable
# ----------------------------
Write-Host "Checking $TempDir..."
if (-not (Test-Path $TempDir)) {
    Write-Host "Creating $TempDir..."
    New-Item -Path $TempDir -ItemType Directory | Out-Null
}

try {
    $TestFile = Join-Path $TempDir "write_test.tmp"
    "test" | Out-File -FilePath $TestFile -ErrorAction Stop
    Remove-Item $TestFile -Force
    Write-Host "OK: Write access to $TempDir verified." -ForegroundColor Green
} catch {
    Write-Error "ERROR: Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 3. Look for installer ZIP files
# ----------------------------
Write-Host "Searching for installer ZIPs in $TempDir..."
$RSCDFile = Get-ChildItem -Path $TempDir -Filter $RSCDPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$TSSAFile = Get-ChildItem -Path $TempDir -Filter $TSSAPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$BAOFile  = Get-ChildItem -Path $TempDir -Filter $BAOPattern  -ErrorAction SilentlyContinue | Select-Object -First 1

$AllMissing = (-not $RSCDFile -and -not $TSSAFile -and -not $BAOFile)

# ----------------------------
# 4. If any missing, look in Downloads
# ----------------------------
if ($AllMissing -or (-not $RSCDFile -or -not $TSSAFile -or -not $BAOFile)) {
    Write-Warning "Some or all installer ZIPs missing from $TempDir."
    Write-Host "Checking Downloads folder..." -ForegroundColor Cyan

    $Patterns = @($RSCDPattern, $TSSAPattern, $BAOPattern)
    foreach ($Pattern in $Patterns) {
        $File = Get-ChildItem -Path $DownloadsDir -Filter $Pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($File) {
            Write-Host "Found $($File.Name) in Downloads. Moving to $TempDir..."
            try {
                Move-Item -Path $File.FullName -Destination $TempDir -Force
            } catch {
                Write-Warning "Could not move $($File.Name). It might still be downloading."
            }
        }
    }

    # Refresh file variables
    $RSCDFile = Get-ChildItem -Path $TempDir -Filter $RSCDPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    $TSSAFile = Get-ChildItem -Path $TempDir -Filter $TSSAPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    $BAOFile  = Get-ChildItem -Path $TempDir -Filter $BAOPattern  -ErrorAction SilentlyContinue | Select-Object -First 1
}

# ----------------------------
# 5. If all still missing, open browser
# ----------------------------
if (-not $RSCDFile -and -not $TSSAFile -and -not $BAOFile) {
    Write-Warning "All required ZIPs missing from both $TempDir and Downloads."
    Write-Host "Please download them from: $BmcSupportUrl" -ForegroundColor Yellow
    Start-Process $BmcSupportUrl
    exit 1
}

# ----------------------------
# 6. Extract ZIPs if needed
# ----------------------------
$FilesToExtract = @($RSCDFile, $TSSAFile, $BAOFile) | Where-Object { $_ -ne $null }

foreach ($File in $FilesToExtract) {
    $ExtractPath = Join-Path $TempDir ([System.IO.Path]::GetFileNameWithoutExtension($File.Name))

    # Determine if the folder exists and whether it has *any* content (files or folders)
    $destinationExists = Test-Path $ExtractPath
    $destinationHasContent = $false
    if ($destinationExists) {
        $contentCount = (Get-ChildItem -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($contentCount -gt 0) { $destinationHasContent = $true }
    }

    if ($destinationExists -and $destinationHasContent) {
        Write-Warning "Skipping extraction: $ExtractPath already exists and contains items."
        continue
    }

    try {
        Write-Host "Extracting $($File.Name)..."
        Expand-Archive -Path $File.FullName -DestinationPath $ExtractPath -Force -ErrorAction Stop
        Write-Host "Extracted $($File.Name)." -ForegroundColor Green
    } catch {
        Write-Warning "Extraction failed for $($File.Name). It may be incomplete or locked."
    }
}

# ----------------------------
# 7. Done
# ----------------------------
Write-Host ""
Write-Host "All files checked. Extraction done where possible." -ForegroundColor Green
