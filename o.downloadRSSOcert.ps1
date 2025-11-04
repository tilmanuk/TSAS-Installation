<#
.SYNOPSIS
    Download Remedy SSO cert and create JKS using AdminPassword from C:\Temp\tsas.config.
#>

# ----------------------------
# 1. Load configuration
# ----------------------------
$ConfigFile = "C:\Temp\tsas.config"

if (-not (Test-Path $ConfigFile)) {
    Write-Host "[error] Configuration file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

try {
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
    $TSASInstallLocation = $Config.TSASInstallLocation
    $AdminPassword = $Config.AdminPassword
} catch {
    Write-Host "[error] Failed to read configuration." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($TSASInstallLocation) -or [string]::IsNullOrWhiteSpace($AdminPassword)) {
    Write-Host "[error] TSASInstallLocation or AdminPassword missing in configuration." -ForegroundColor Red
    exit 1
}

# ----------------------------
# 2. Prepare directories
# ----------------------------
$RSSODir = Join-Path $TSASInstallLocation "RSSO"
if (-not (Test-Path $RSSODir)) {
    try {
        New-Item -Path $RSSODir -ItemType Directory -Force | Out-Null
        Write-Host "[ok] Created RSSO directory: $RSSODir" -ForegroundColor Green
    } catch {
        Write-Host "[error] Could not create RSSO directory." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ok] Using RSSO directory: $RSSODir" -ForegroundColor Green
}

# ----------------------------
# 3. Read creds.json for endpoint info
# ----------------------------
$CredsFile = Join-Path $TSASInstallLocation "Server Automation Connector\Config\creds.json"

if (-not (Test-Path $CredsFile)) {
    Write-Host "[error] creds.json not found at expected location." -ForegroundColor Red
    exit 1
}

try {
    $Creds = Get-Content $CredsFile | ConvertFrom-Json
    $RemedySSOUrl = $Creds.endpoints.ifm
    if ([string]::IsNullOrWhiteSpace($RemedySSOUrl)) {
        throw
    }
    Write-Host "[ok] Found RemedySSO URL." -ForegroundColor Green
    Write-Host "[info] The RemedySSO URL will be: $RemedySSOUrl" -ForegroundColor Cyan
} catch {
    Write-Host "[error] Failed to read RemedySSO URL from creds.json." -ForegroundColor Red
    exit 1
}

# ----------------------------
# 4. Download SSL certificate
# ----------------------------
$CertFile = Join-Path $RSSODir "rsso.crt"
$JKSFile = Join-Path $RSSODir "rsso.jks"

Write-Host "[info] Retrieving SSL certificate from RemedySSO..." -ForegroundColor Cyan

try {
    $HostName = ($RemedySSOUrl -replace '^https?://', '') -replace '/.*$', ''
    $Port = 443

    $TcpClient = New-Object System.Net.Sockets.TcpClient($HostName, $Port)
    $acceptAll = { param($sender,$cert,$chain,$errors) return $true }
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] $acceptAll
    $SslStream = New-Object System.Net.Security.SslStream($TcpClient.GetStream(), $false, $callback)
    $SslStream.AuthenticateAsClient($HostName)

    $raw = $SslStream.RemoteCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    [System.IO.File]::WriteAllBytes($CertFile, $raw)

    $SslStream.Close()
    $TcpClient.Close()

    Write-Host "[ok] Certificate saved as $CertFile" -ForegroundColor Green
} catch {
    Write-Host "[error] Failed to retrieve SSL certificate." -ForegroundColor Red
    exit 1
}

# ----------------------------
# 5. Locate keytool.exe under TSASInstallLocation
# ----------------------------
Write-Host "[info] Searching for keytool.exe under TSAS install location..." -ForegroundColor Cyan

try {
    $KeytoolPath = Get-ChildItem -Path $TSASInstallLocation -Recurse -Filter "keytool.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty FullName
} catch {
    $KeytoolPath = $null
}

if ([string]::IsNullOrWhiteSpace($KeytoolPath) -or -not (Test-Path $KeytoolPath)) {
    Write-Host "[error] keytool.exe not found under TSAS install location." -ForegroundColor Red
    exit 1
}

Write-Host "[ok] Found keytool: $KeytoolPath" -ForegroundColor Green

# ----------------------------
# 6. Import cert into JKS
# ----------------------------
Write-Host "[info] Importing certificate into keystore..." -ForegroundColor Cyan

$LogFile = "C:\Temp\rssocert.log"

try {
    $args = @(
        "-importcert",
        "-file", $CertFile,
        "-keystore", $JKSFile,
        "-alias", "rsso",
        "-storepass", $AdminPassword,
        "-noprompt"
    )

    # Run keytool and capture output to log file
    Write-Host "[info] Logging output to $LogFile" -ForegroundColor Cyan
    & $KeytoolPath @args *> $LogFile 2>&1
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        Write-Host "[error] keytool failed with exit code $ExitCode. See log for details: $LogFile" -ForegroundColor Red
        exit $ExitCode
    } else {
        Write-Host "[ok] Certificate imported into keystore successfully." -ForegroundColor Green
    }
} catch {
    Write-Host "[error] Failed to create keystore." -ForegroundColor Red
    Write-Host "[info] See log for details: $LogFile" -ForegroundColor Yellow
    exit 1
}

# ----------------------------
# 7. Verify keystore contains alias
# ----------------------------
Write-Host "[info] Verifying keystore content..." -ForegroundColor Cyan

try {
    $listArgs = @("-list","-keystore",$JKSFile,"-storepass",$AdminPassword)
    $output = & $KeytoolPath $listArgs 2>&1
    if ($output -and ($output -match "rsso")) {
        Write-Host "[ok] Alias 'rsso' found in keystore." -ForegroundColor Green
    } else {
        Write-Host "[warning] Alias 'rsso' not found in keystore." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[warning] Could not verify keystore contents." -ForegroundColor Yellow
}

# ----------------------------
# 8. Summary
# ----------------------------
Write-Host "[ok] Completed. Certificate and keystore are located here:" -ForegroundColor Green
Write-Host "      Certificate: $CertFile" -ForegroundColor Cyan
Write-Host "      Keystore:   $JKSFile" -ForegroundColor Cyan
Write-Host "[info] Keystore password used is the AdminPassword from tsas.config." -ForegroundColor Cyan