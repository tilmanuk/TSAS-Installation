# Run as Administrator

# ----------------------------
# Configuration
# ----------------------------
$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
$ValueName = "DisabledComponents"
# Value 0xFF = disable IPv6 on all non-tunnel and tunnel interfaces (per Microsoft guidance)
$ValueData = 0xFF

# ----------------------------
# 1. Backup current registry value (optional but recommended)
# ----------------------------
Write-Host "Backing up existing DisabledComponents value (if exists)..."
if (Test-Path $RegPath) {
    $old = Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -ne $old) {
        $oldValue = $old.$ValueName
        Write-Host "Current DisabledComponents = $oldValue"
        # Export a backup
        $backupFile = "C:\Temp\IPv6_DisabledComponents_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        Write-Host "Exporting backup to $backupFile"
        reg export "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" $backupFile /y > $null
    } else {
        Write-Host "No existing DisabledComponents value found."
    }
} else {
    Write-Host "Registry path not found - something unexpected."
}

# ----------------------------
# 2. Set the registry value to disable IPv6
# ----------------------------
Write-Host "Setting DisabledComponents = 0x$("{0:X}" -f $ValueData) in $RegPath"
try {
    New-ItemProperty -Path $RegPath -Name $ValueName -PropertyType DWORD -Force -Value $ValueData | Out-Null
    Write-Host "[OK] Registry updated successfully." -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to update registry: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# 3. Inform user that restart is needed
# ----------------------------
Write-Host ""
Write-Host "[WARNING] You must restart the computer for changes to take effect." -ForegroundColor Yellow

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
