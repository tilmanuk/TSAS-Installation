# ----------------------------
# 1. Configuration
# ----------------------------
$TempDir = "C:\Temp"
$DownloadsDir = Join-Path $env:USERPROFILE "Downloads"
$RSCDPattern    = "TSSA???-RSCDAgents.zip"
$TSSAPattern    = "TSSA???-WIN64.zip"
$BAORepoPattern = "windows_bao_server_installer_??_?_??.zip"
$BAOContentPattern = "windows_bao_content_installer_??.?.??.??.zip"
$BmcSupportUrl  = "https://support.bmc.com"

# ----------------------------
# 3. Look for installer ZIP files
# ----------------------------
Write-Host "Searching for installer ZIPs in $TempDir..."
$RSCDFile        = Get-ChildItem -Path $TempDir -Filter $RSCDPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$TSSAFile        = Get-ChildItem -Path $TempDir -Filter $TSSAPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$BAORepoFile     = Get-ChildItem -Path $TempDir -Filter $BAORepoPattern -ErrorAction SilentlyContinue | Select-Object -First 1
$BAOContentFile  = Get-ChildItem -Path $TempDir -Filter $BAOContentPattern -ErrorAction SilentlyContinue | Select-Object -First 1

$AllMissing = (-not $RSCDFile -and -not $TSSAFile -and -not $BAORepoFile -and -not $BAOContentFile)

# ----------------------------
# 4. If any missing, look in Downloads
# ----------------------------
if ($AllMissing -or (-not $RSCDFile -or -not $TSSAFile -or -not $BAORepoFile -or -not $BAOContentFile)) {
    Write-Warning "Some or all installer ZIPs missing from $TempDir."
    Write-Host "Checking Downloads folder..." -ForegroundColor Cyan

    $Patterns = @($RSCDPattern, $TSSAPattern, $BAORepoPattern, $BAOContentPattern)
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
    $RSCDFile        = Get-ChildItem -Path $TempDir -Filter $RSCDPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    $TSSAFile        = Get-ChildItem -Path $TempDir -Filter $TSSAPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    $BAORepoFile     = Get-ChildItem -Path $TempDir -Filter $BAORepoPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    $BAOContentFile  = Get-ChildItem -Path $TempDir -Filter $BAOContentPattern -ErrorAction SilentlyContinue | Select-Object -First 1
}

# ----------------------------
# 5. If all still missing, open browser
# ----------------------------
if (-not $RSCDFile -and -not $TSSAFile -and -not $BAORepoFile -and -not $BAOContentFile) {
    Write-Warning "All required ZIPs missing from both $TempDir and Downloads."
    Write-Host "Please download them from: $BmcSupportUrl" -ForegroundColor Yellow
    Start-Process $BmcSupportUrl
    exit 1
}

# ----------------------------
# 6. Extract ZIPs if needed
# ----------------------------
$FilesToExtract = @($RSCDFile, $TSSAFile, $BAORepoFile, $BAOContentFile) | Where-Object { $_ -ne $null }

foreach ($File in $FilesToExtract) {
    $ExtractPath = Join-Path $TempDir ([System.IO.Path]::GetFileNameWithoutExtension($File.Name))

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
