<#
    CheckServices.ps1
    Ensures SQL + TSAS + BAO + TSO services start in correct order.
    Supports /restart for full controlled stop/start.

    Uses ForegroundColor (no ANSI) for info/warn/error/ok output.
#>

# --------------------------
# Script Parameters
# --------------------------
param(
    [switch]$Restart
)

# --------------------------
# Helper Output Functions
# --------------------------
function Write-Info($msg)  { Write-Host $msg -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host $msg -ForegroundColor Red }

# --------------------------
# Load config for SQL instance
# --------------------------
$ConfigPath = "C:\Temp\tsas.config"

if (!(Test-Path $ConfigPath)) {
    Write-Err "Config file not found: $ConfigPath"
    exit 1
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Err "Failed to parse config JSON: $($_.Exception.Message)"
    exit 1
}

$SQLInstance = $Config.SQLInstance
if ([string]::IsNullOrWhiteSpace($SQLInstance)) {
    Write-Err "SQLInstance not found in config file."
    exit 1
}

# SQL service name is dynamically constructed
$SQLServiceName = "MSSQL`$$SQLInstance"

# --------------------------
# SERVICES (IN START ORDER)
# --------------------------
$ServiceList = @(
    $SQLServiceName,
    "BladeApp Server",
    "bmc-server-automation-connector",
    "BAO-REPO",
    "BAO-CDP",
    "tso-connector"
)

# --------------------------
# Restart flag check
# --------------------------
if ($Restart) {
    Write-Warn "Restart flag detected -- performing controlled stop/start..."
}

# --------------------------
# Service Start Helper
# --------------------------
function Start-ServiceSafe {
    param(
        [string]$Name,
        [int]$TimeoutSec = 600,
        [int]$PollSec = 5
    )

    if (!(Get-Service -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Err "Service not found: $Name"
        return
    }

    Write-Info "Starting service: $Name"
    Start-Service -Name $Name -ErrorAction SilentlyContinue

    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $status = (Get-Service -Name $Name).Status
        if ($status -eq 'Running') {
            Write-OK "Service is running: $Name"
            return
        }
        Start-Sleep $PollSec
        $elapsed += $PollSec
        Write-Host ("Waiting for {0}... {1}/{2}s" -f $Name, $elapsed, $TimeoutSec)
    }

    Write-Err "Timeout! Service did not start: $Name"
}

# --------------------------
# Service Stop Helper
# --------------------------
function Stop-ServiceSafe {
    param(
        [string]$Name,
        [int]$TimeoutSec = 300,
        [int]$PollSec = 5
    )

    if (!(Get-Service -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Warn "Service not found (skip stop): $Name"
        return
    }

    Write-Info "Stopping service: $Name"
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue

    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $status = (Get-Service -Name $Name).Status
        if ($status -eq 'Stopped') {
            Write-OK "Service stopped: $Name"
            return
        }
        Start-Sleep $PollSec
        $elapsed += $PollSec
        Write-Host ("Waiting for {0} to stop... {1}/{2}s" -f $Name, $elapsed, $TimeoutSec)
    }

    Write-Warn "Timeout! Service did not stop: $Name"
}

# --------------------------
# RESTART MODE
# --------------------------
if ($Restart) {
    Write-Info "Stopping services in reverse order..."
    $Reversed = $ServiceList.Clone()
    [Array]::Reverse($Reversed)

    foreach ($svc in $Reversed) {
        Stop-ServiceSafe -Name $svc
    }

    Write-Info "Starting services in correct order..."
    foreach ($svc in $ServiceList) {
        Start-ServiceSafe -Name $svc
    }

    Write-OK "Restart sequence complete."
    exit 0
}

# --------------------------
# NORMAL MODE - ENSURE RUNNING
# --------------------------
Write-Info "Checking services in order..."

foreach ($svc in $ServiceList) {
    $exists = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if (!$exists) {
        Write-Err "Service not found: $svc"
        continue
    }

    if ($exists.Status -eq "Running") {
        Write-OK "$svc is already running."
    } else {
        Write-Warn "$svc is not running -- starting..."
        Start-ServiceSafe -Name $svc
    }
}

Write-OK "All services validated."