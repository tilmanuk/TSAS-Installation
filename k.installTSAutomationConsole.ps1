
<#
.SYNOPSIS
    Prepares TSAC installer options and runs TSSACONSOLE installer silently.
#>

# ------------------------------------------------------------
# Modify Terminal Server temporary directory registry settings
# ------------------------------------------------------------

try {
    # ----------------------------
    # 1. Registry path and values
    # ----------------------------
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    $ValuesToSet = @{
        "PerSessionTempDir"      = 0
        "DeleteTempDirsOnExit"   = 0
    }

    # ----------------------------
    # 2. Ensure we can write to HKLM
    # ----------------------------
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        throw "❌ Administrator privileges are required to modify HKLM registry keys."
    }

    # ----------------------------
    # 3. Set registry values
    # ----------------------------
    foreach ($name in $ValuesToSet.Keys) {
        Write-Host "Setting $name to $($ValuesToSet[$name]) in $RegPath..."
        Set-ItemProperty -Path $RegPath -Name $name -Value $ValuesToSet[$name] -Type DWord -Force
        Write-Host "✅ $name updated successfully."
    }

} catch {
    Write-Error "⚠️ Failed to update registry: $_"
}

# ----------------------------
# 1. Ensure C:\Temp exists and is writable
# ----------------------------
$TempDir = "C:\Temp"
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
# 2. Load JSON configuration
# ----------------------------
$ConfigFile = Join-Path $TempDir "tsas.config"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "❌ Configuration file not found: $ConfigFile"
    exit 1
}

try {
    $Config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "❌ Failed to parse configuration file as JSON: $($_.Exception.Message)"
    exit 1
}

$TSASInstallLocation = $Config.TSASInstallLocation
if (-not $TSASInstallLocation) {
    Write-Error "❌ TSASInstallLocation not found in configuration file."
    exit 1
}

# ----------------------------
# 3. Append \TSAC to install location
# ----------------------------
$InstallRoot = Join-Path $TSASInstallLocation "TSAC"

# ----------------------------
# 4. Create tsac.ssi file
# ----------------------------
$SsiFile = Join-Path $TempDir "tsac.ssi"
$SsiContent = @"
-P installLocation=$InstallRoot
-J IS_UPGRADE=false
-A featureClientUtilities
-A featureNetworkShell
-A featureConfigurationManagerConsole
-A featureRCPUpgradeService
"@

try {
    $SsiContent | Out-File -FilePath $SsiFile -Encoding ASCII -Force
    Write-Host "✅ Created SSI file at $SsiFile with install location: $InstallRoot"
} catch {
    Write-Error "❌ Failed to create SSI file: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# 5. Find TSSACONSOLE???-WIN64.exe
# ----------------------------
$InstallerFolder = "C:\Temp\Disk1\files\installers\rcp"
$InstallerPattern = "TSSACONSOLE???-WIN64.exe"

$Installer = Get-ChildItem -Path $InstallerFolder -Filter $InstallerPattern | Select-Object -First 1

if (-not $Installer) {
    Write-Host "⚠️ Could not find installer matching '$InstallerPattern' in $InstallerFolder"
    Write-Host "Please download the TSAC installer from support.bmc.com"
    Start-Process "https://support.bmc.com" -UseNewEnvironment
    exit 1
}

Write-Host "✅ Found installer: $($Installer.FullName)"

# ----------------------------
# 6. Run TSSACONSOLE installer silently
# ----------------------------
try {
    Write-Host "Running TSAC installer silently..."
    Start-Process -FilePath $Installer.FullName -ArgumentList "-i silent -DOPTIONS_FILE=`"$SsiFile`"" -Wait -NoNewWindow
    Write-Host "✅ TSAC installation completed successfully."
} catch {
    Write-Error "❌ TSAC installation failed: $($_.Exception.Message)"
    exit 1
}
