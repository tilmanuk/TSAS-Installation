<#
.SYNOPSIS
    Installs SQL Server Express 2022 using values from c:\temp\tsas.config
#>

# ----------------------------
# 1. Load configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    exit 1
}

try {
    $ConfigJson = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to read/parse config file: $($_.Exception.Message)"
    exit 1
}

# Validate required values
if (-not $ConfigJson.SQLInstance -or [string]::IsNullOrWhiteSpace($ConfigJson.SQLInstance)) {
    Write-Error "SQLInstance is missing from $ConfigFile. Cannot continue."
    exit 1
}

if (-not $ConfigJson.AdminPassword -or [string]::IsNullOrWhiteSpace($ConfigJson.AdminPassword)) {
    Write-Error "AdminPassword is missing from $ConfigFile. Cannot continue."
    exit 1
}

$SQLInstance = $ConfigJson.SQLInstance
$SAPWD = $ConfigJson.AdminPassword

# ----------------------------
# 2. Download SQL Express bootstrapper
# ----------------------------
$TempDir = "C:\Temp"
$InstallerUrl = "https://go.microsoft.com/fwlink/p/?linkid=2216019&clcid=0x809&culture=en-gb&country=gb"
$InstallerPath = Join-Path $TempDir "SQL2022-SSEI-Expr.exe"

# Ensure temp folder exists and writable
if (-not (Test-Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory | Out-Null }
try {
    $TestFile = Join-Path $TempDir "write_test.tmp"
    "test" | Out-File $TestFile -ErrorAction Stop
    Remove-Item $TestFile -Force
} catch {
    Write-Error "Cannot write to $TempDir. Run as Administrator."
    exit 1
}

if (-not (Test-Path $InstallerPath)) {
    Write-Host "Downloading SQL Server Express bootstrapper..."
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ Download complete: $InstallerPath"
    } catch {
        Write-Error "Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "⚙️ Using existing installer: $InstallerPath"
}

# ----------------------------
# 3. Run installer
# ----------------------------
Write-Host "🛠️ Installing SQL Server Express 2022 (Instance: $SQLInstance)..."

$Arguments = "/Action=Install /IAcceptSQLServerLicenseTerms /Quiet /InstanceName=$SQLInstance /SAPWD=$SAPWD /Features=SQLEngine /TCPEnabled=1"

try {
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -eq 0) {
        Write-Host "✅ SQL Server Express installation completed successfully."
    } else {
        Write-Error "❌ SQL Server Express installation failed. Exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
} catch {
    Write-Error "❌ Failed to launch installer: $($_.Exception.Message)"
    exit 1
}
