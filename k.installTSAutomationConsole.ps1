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

