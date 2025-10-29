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
# Escape single quotes in password for safe SQL
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

Write-Host "🎉 SQL setup complete."
