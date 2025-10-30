<#
.SYNOPSIS
    Creates a SQL Server database and admin login using JSON config from C:\Temp\tsas.config
#>

# ----------------------------
# 1. Ensure SqlServer module is installed
# ----------------------------
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "SqlServer module not found. Installing from PSGallery..."
    try {
        Install-Module -Name SqlServer -Force -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
        Write-Host "✅ SqlServer module installed."
    } catch {
        Write-Error "❌ Failed to install SqlServer module: $($_.Exception.Message)"
        exit 1
    }
}

Import-Module SqlServer -ErrorAction Stop

# ----------------------------
# 2. Load JSON configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"

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

# ----------------------------
# 3. Extract variables from JSON
# ----------------------------
$Hostname      = $Config.Hostname
$SQLInstance   = $Config.SQLInstance
$SQLDBName     = $Config.SQLDBName
$AdminUser     = $Config.AdminUser
$AdminPassword = $Config.AdminPassword

# Validate
$Missing = @()
foreach ($key in 'Hostname','SQLInstance','SQLDBName','AdminUser','AdminPassword') {
    if (-not $Config.$key) { $Missing += $key }
}
if ($Missing.Count -gt 0) {
    Write-Error "❌ Missing required keys in configuration file: $($Missing -join ', ')"
    exit 1
}

# ----------------------------
# 4. Build server instance and test connectivity
# ----------------------------
$ServerInstance = "$Hostname\$SQLInstance"
Write-Host "Connecting to SQL Server instance: $ServerInstance"

try {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -Username 'sa' -Password $AdminPassword -Query "SELECT 1" -ErrorAction Stop -TrustServerCertificate -Encrypt Optional | Out-Null
    Write-Host "✅ Connected to SQL Server."
} catch {
    Write-Error "❌ Cannot connect to SQL Server as 'sa'. Error: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# 5. Create database if it doesn’t exist
# ----------------------------
$SqlCreateDb = @"
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$SQLDBName')
BEGIN
    PRINT 'Creating database [$SQLDBName]...';
    CREATE DATABASE [$SQLDBName];
END
ELSE
BEGIN
    PRINT 'Database [$SQLDBName] already exists.';
END
"@

Invoke-Sqlcmd -ServerInstance $ServerInstance -Username 'sa' -Password $AdminPassword -Query $SqlCreateDb -ErrorAction Stop -TrustServerCertificate -Encrypt Optional
Write-Host "✅ Database '$SQLDBName' created or verified."

# ----------------------------
# 6. Create login and assign sysadmin
# ----------------------------
$EscapedPassword = $AdminPassword -replace "'", "''"

$SqlLogin = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$AdminUser')
BEGIN
    CREATE LOGIN [$AdminUser] WITH PASSWORD = N'$EscapedPassword', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
    PRINT 'Login [$AdminUser] created.';
END
ELSE
BEGIN
    PRINT 'Login [$AdminUser] already exists.';
END

IF NOT EXISTS (
    SELECT 1 FROM sys.server_role_members rm
    JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
    JOIN sys.server_principals p ON rm.member_principal_id = p.principal_id
    WHERE r.name = N'sysadmin' AND p.name = N'$AdminUser'
)
BEGIN
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [$AdminUser];
    PRINT 'Granted sysadmin role to [$AdminUser].';
END
"@

Invoke-Sqlcmd -ServerInstance $ServerInstance -Username 'sa' -Password $AdminPassword -Query $SqlLogin -ErrorAction Stop -TrustServerCertificate -Encrypt Optional
Write-Host "✅ Login '$AdminUser' verified and granted sysadmin."

# ----------------------------
# 7. Create database user and grant db_owner
# ----------------------------
$SqlUser = @"
USE [$SQLDBName];

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$AdminUser')
BEGIN
    CREATE USER [$AdminUser] FOR LOGIN [$AdminUser];
    PRINT 'Created database user [$AdminUser].';
END

IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members drm
    JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
    JOIN sys.database_principals p ON drm.member_principal_id = p.principal_id
    WHERE r.name = N'db_owner' AND p.name = N'$AdminUser'
)
BEGIN
    ALTER ROLE [db_owner] ADD MEMBER [$AdminUser];
    PRINT 'Granted db_owner role to [$AdminUser].';
END
"@

Invoke-Sqlcmd -ServerInstance $ServerInstance -Username 'sa' -Password $AdminPassword -Database $SQLDBName -Query $SqlUser -ErrorAction Stop -TrustServerCertificate -Encrypt Optional
Write-Host "✅ Database user '$AdminUser' created/verified and granted db_owner on '$SQLDBName'."

# ------------------------------------------------------------
# Configure SQL Server TCP/IP Ports from tsas.config
# ------------------------------------------------------------

try {
    # Base registry path for SQL Server
    $BaseRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"

    # Find the instance key matching MSSQL??.{SQLInstance}
    $InstanceKey = Get-ChildItem $BaseRegPath | Where-Object { $_.PSChildName -match "MSSQL\d+\.$SQLInstance" }

    if (-not $InstanceKey) {
        throw "❌ SQL Server registry instance key not found for instance '$SQLInstance'"
    }

    # TCP key path
    $TcpKeyPath = Join-Path $InstanceKey.PSPath "MSSQLServer\SuperSocketNetLib\Tcp"

    if (-not (Test-Path $TcpKeyPath)) {
        throw "❌ Tcp registry path not found: $TcpKeyPath"
    }

    Write-Host "✅ Found TCP registry path: $TcpKeyPath"

    # Get all subkeys (IP1, IP2, ..., IPAll)
    $IPSubKeys = Get-ChildItem $TcpKeyPath

    foreach ($IPKey in $IPSubKeys) {
        Write-Host "🔧 Updating $($IPKey.PSChildName)..."

        # Active and Enabled are REG_DWORD (ignore IPAll)
        if ($IPKey.PSChildName -ne "IPAll") {
            Set-ItemProperty -Path $IPKey.PSPath -Name "Active" -Value 1 -Type DWord -ErrorAction Stop
            Set-ItemProperty -Path $IPKey.PSPath -Name "Enabled" -Value 1 -Type DWord -ErrorAction Stop
        }

        # TcpDynamicPorts and TcpPort are REG_SZ
        Set-ItemProperty -Path $IPKey.PSPath -Name "TcpDynamicPorts" -Value "" -Type String -ErrorAction Stop
        Set-ItemProperty -Path $IPKey.PSPath -Name "TcpPort" -Value "1433" -Type String -ErrorAction Stop

        Write-Host "✅ $($IPKey.PSChildName) updated successfully."
    }

} catch {
    Write-Error "⚠️ Failed to update SQL Server TCP/IP ports: $_"
}

# ----------------------------
# 8. Restart SQL Server service
# ----------------------------
try {
    $ServiceName = "MSSQL`$$SQLInstance"  # Use backtick to escape the $ in the service name
    Write-Host "🔄 Restarting SQL Server service: $ServiceName ..."
    
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        Write-Host "✅ SQL Server service '$ServiceName' restarted successfully."
    } else {
        Write-Warning "⚠️ SQL Server service '$ServiceName' not found."
    }
} catch {
    Write-Error "❌ Failed to restart SQL Server service '$ServiceName': $_"
}

Write-Host "🎉 SQL setup complete."