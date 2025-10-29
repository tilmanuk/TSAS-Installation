<#
.SYNOPSIS
    Downloads and installs Microsoft SQLCMD utilities silently (with license acceptance and PATH refresh).
#>

# ----------------------------
# Configuration
# ----------------------------
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2230791"
$TempDir = "C:\Temp"
$InstallerPath = Join-Path $TempDir "MsSqlCmdLnUtils.msi"
$LogFile = Join-Path $TempDir "MsSqlCmdLnUtils_Install.log"

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
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
    Write-Host "✅ Verified write access to $TempDir"
} catch {
    Write-Error "❌ Cannot write to $TempDir. Please run as Administrator."
    exit 1
}

# ----------------------------
# 2. Download the installer
# ----------------------------
if (-not (Test-Path $InstallerPath)) {
    Write-Host "Downloading SQLCMD installer from Microsoft..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ Download complete: $InstallerPath"
    } catch {
        Write-Error "❌ Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "⚙️ Using existing file: $InstallerPath"
}

# ----------------------------
# 3. Install the MSI silently
# ----------------------------
if (Test-Path $InstallerPath) {
    Write-Host "Installing SQLCMD silently (accepting license terms)..."
    
    # ✅ Added required license acceptance property
    $Arguments = "/i `"$InstallerPath`" /qn /norestart /log `"$LogFile`" IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "✅ SQLCMD installation completed successfully."
    } else {
        Write-Error "❌ SQLCMD installation failed. Exit code: $($process.ExitCode). Check log: $LogFile"
        exit $process.ExitCode
    }
} else {
    Write-Error "❌ Installer file not found at $InstallerPath."
    exit 1
}

# ----------------------------
# 4. Reload system PATH
# ----------------------------
Write-Host "Refreshing system PATH environment variable..."
try {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + `
                 [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Write-Host "✅ PATH successfully refreshed."
} catch {
    Write-Warning "⚠️ Unable to refresh PATH automatically. You may need to restart PowerShell."
}

# ----------------------------
# 5. Verify sqlcmd in PATH
# ----------------------------
Write-Host "Verifying sqlcmd installation..."
$SqlCmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source

if ($SqlCmdPath) {
    Write-Host "✅ sqlcmd is installed and available at: $SqlCmdPath"
    try {
        $version = sqlcmd -? | Select-String -Pattern "Version"
        if ($version) { Write-Host "✅ sqlcmd test run successful." }
    } catch {
        Write-Warning "⚠️ sqlcmd found but failed to execute properly."
    }
} else {
    Write-Error "❌ sqlcmd not found in PATH. You may need to restart PowerShell or log off/on."
}