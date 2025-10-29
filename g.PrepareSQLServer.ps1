<#
.SYNOPSIS
    Enables TCP/IP on all SQL Server instances on the local machine using SMO WMI.
    Automatically installs the SqlServer PowerShell module if missing.
#>

# ----------------------------
# 1. Ensure SqlServer module is installed
# ----------------------------
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "SqlServer module not found. Installing from PSGallery..."
    try {
        Install-Module -Name SqlServer -Force -Repository PSGallery -Scope CurrentUser
        Write-Host "✅ SqlServer module installed."
    } catch {
        Write-Error "❌ Failed to install SqlServer module: $_"
        exit 1
    }
}

Import-Module SqlServer -ErrorAction Stop

# ----------------------------
# 2. Load SMO WMI assembly
# ----------------------------
try {
    Add-Type -AssemblyName "Microsoft.SqlServer.SqlWmiManagement" -ErrorAction Stop
} catch {
    Write-Error "❌ Could not load Microsoft.SqlServer.SqlWmiManagement assembly. Ensure SMO is installed."
    exit 1
}

# ----------------------------
# 3. Connect to local SQL Server via WMI
# ----------------------------
try {
    $wmi = New-Object 'Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer' 'localhost'
} catch {
    Write-Error "❌ Failed to instantiate ManagedComputer object. $_"
    exit 1
}

# ----------------------------
# 4. Enumerate all instances and enable TCP/IP
# ----------------------------
foreach ($instanceKey in $wmi.ServerInstances.Keys) {
    $instance = $wmi.ServerInstances[$instanceKey]
    Write-Host "Configuring instance: $instanceKey"

    # Enable TCP/IP
    $tcp = $instance.ServerProtocols['Tcp']
    if ($tcp.IsEnabled) {
        Write-Host "✅ TCP/IP is already enabled for $instanceKey."
    } else {
        $tcp.IsEnabled = $true
        $tcp.Alter()
        Write-Host "✅ TCP/IP enabled for $instanceKey."
    }

    # Restart the SQL Server service
    $serviceName = $instance.ServiceName
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Restarting SQL Server service $serviceName ..."
        Restart-Service -Name $serviceName -Force
        Write-Host "✅ SQL Server service restarted."
    } else {
        Write-Warning "⚠️ SQL Server service $serviceName not found."
    }
}

Write-Host "🎉 TCP/IP configuration complete for all SQL Server instances."