# j.RunSQLServerMaster.ps1
# ------------------------------------------------------
# Runs sqlserver_master.bat with parameters from tsas.config
# ------------------------------------------------------

try {
    # ----------------------------
    # 1. Define paths
    # ----------------------------
    $ConfigPath = "C:\Temp\tsas.config"
    $ScriptDir  = "C:\Temp\Disk1\files\configurations\db_scripts\sqlserver"
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
