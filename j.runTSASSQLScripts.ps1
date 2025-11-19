# j.RunSQLServerMaster.ps1
# ------------------------------------------------------
# Runs sqlserver_master.bat with parameters from tsas.config
# ------------------------------------------------------

try {
    # ----------------------------
    # 1. Define paths
    # ----------------------------
    $ConfigPath = "C:\Temp\tsas.config"
# ----------------------------
# Locate SQL Server DB scripts directory
# ----------------------------
$BaseDir = "C:\Temp"

# Locate the extracted TSSA???-WIN64 folder
$ExtractedDir = Get-ChildItem -Path $BaseDir -Directory -Filter "TSSA???-WIN64" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $ExtractedDir) {
    Write-Host "[ERROR] Could not locate extracted folder matching TSSA???-WIN64 in $BaseDir" -ForegroundColor Red
    Write-Host "[INFO] Please extract the TSAA installer ZIP to $BaseDir" -ForegroundColor Cyan
    exit 1
}

# Construct the full path to the SQL Server DB scripts
$ScriptDir = Join-Path $ExtractedDir.FullName "Disk1\files\configurations\db_scripts\sqlserver"

if (-not (Test-Path $ScriptDir)) {
    Write-Host "[ERROR] SQL Server DB scripts directory not found: $ScriptDir" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] SQL Server DB scripts directory located at: $ScriptDir" -ForegroundColor Green
    $BatchFile  = "sqlserver_master.bat"

    # Save current working directory to restore later
    $OriginalDir = Get-Location

    Write-Host "[INFO] Reading configuration from $ConfigPath..." -ForegroundColor Cyan

    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at $ConfigPath"
    }

    # ----------------------------
    # 2. Parse tsas.config JSON
    # ----------------------------
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    $SQLServer = "$($Config.Hostname)\$($Config.SQLInstance)"
    $Database  = $Config.SQLDBName
    $User      = $Config.AdminUser
    $Password  = $Config.AdminPassword

    Write-Host "[OK] Configuration loaded:" -ForegroundColor Green
    Write-Host "   SQL Server : $SQLServer"
    Write-Host "   Database   : $Database"
    Write-Host "   User       : $User"

    # ----------------------------
    # 3. Change directory to where the batch file is
    # ----------------------------
    if (-not (Test-Path $ScriptDir)) {
        throw "SQL script directory not found: $ScriptDir"
    }
    Set-Location $ScriptDir
    Write-Host "[INFO] Changed directory to: $ScriptDir" -ForegroundColor Cyan

    $BatchPath = Join-Path $ScriptDir $BatchFile
    if (-not (Test-Path $BatchPath)) {
        throw "Batch file not found: $BatchPath"
    }

    # ----------------------------
    # 4. Build arguments
    # ----------------------------
    $Arguments = "`"$SQLServer`" `"$Database`" `"$User`" `"$Password`""
    Write-Host "[INFO] Running: $BatchFile $Arguments" -ForegroundColor Cyan

    # ----------------------------
    # 5. Execute batch file
    # ----------------------------
    $process = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c `"$BatchPath $Arguments`"" `
        -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "[OK] SQL master script completed successfully." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] SQL master script failed with exit code $($process.ExitCode)"
    }

} catch {
    Write-Error "[WARN] Error: $_"
} finally {
    # ----------------------------
    # 6. Restore original directory
    # ----------------------------
    if ($OriginalDir) {
        Set-Location $OriginalDir
        Write-Host "[INFO] Returned to original directory: $OriginalDir" -ForegroundColor Cyan
    }
}

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
