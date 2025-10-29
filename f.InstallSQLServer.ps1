<#
.SYNOPSIS
    Downloads and installs Microsoft SQL Server Express 2022 silently using the official bootstrapper.
    Post-install configuration (instance name, TCP/IP, authentication) should be done separately.
#>

# ----------------------------
# Configuration
# ----------------------------
$DownloadUrl  = "https://go.microsoft.com/fwlink/p/?linkid=2216019&clcid=0x809&culture=en-gb&country=gb"
$TempDir      = "C:\Temp"
$InstallerExe = Join-Path $TempDir "SQL2022-SSEI-Expr.exe"
$MediaPath    = Join-Path $TempDir "SQL2022"
$InstallPath  = "C:\Program Files\Microsoft SQL Server"

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
    Write-Host "✅ Verified write access to $TempDir"
} catch {
    Write-Error "❌ Cannot write to $TempDir. Please run PowerShell as Administrator."
    exit 1
}

# ----------------------------
# 2. Download installer if not already present
# ----------------------------
if (-not (Test-Path $InstallerExe)) {
    Write-Host "Downloading SQL Server Express bootstrapper..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerExe -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ Download complete: $InstallerExe"
    } catch {
        Write-Error "❌ Failed to download installer: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "⚙️ Using existing file: $InstallerExe"
}

# ----------------------------
# 3. Install SQL Server Express silently (bootstrapper)
# ----------------------------
Write-Host "🛠️ Installing SQL Server Express 2022 (silent)..."

$InstallArgs = @(
    "/Action=Install",
    "/MediaPath=$MediaPath",
    "/IAcceptSQLServerLicenseTerms",
    "/Quiet"
)

$install = Start-Process -FilePath $InstallerExe -ArgumentList $InstallArgs -Wait -PassThru

if ($install.ExitCode -eq 0) {
    Write-Host "✅ SQL Server Express installed successfully."
} else {
    Write-Error "❌ SQL Server installation failed. Exit code: $($install.ExitCode)"
    Write-Host "⚠️ Try running manually to debug:"
    Write-Host "`"$InstallerExe`" $($InstallArgs -join ' ')"
    exit $install.ExitCode
}

# ----------------------------
# 4. Verify default SQL Server service
# ----------------------------
Write-Host "🔍 Checking default SQL Server service (MSSQL$SQLEXPRESS)..."
$ServiceName = 'MSSQL$SQLEXPRESS'
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($Service) {
    if ($Service.Status -ne 'Running') {
        Write-Host "Starting SQL Server service..."
        Start-Service -Name $ServiceName
    }
    Write-Host "✅ SQL Server service is running: $($Service.Status)"
} else {
    Write-Warning "⚠️ Could not find default SQL Server service."
}

Write-Host "🎉 Installation process complete."