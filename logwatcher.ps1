param(
    [Parameter(Mandatory = $true)]
    [string]$ListFile
)

Write-Host "`n=== Multi-Log Watcher Started ===`n" -ForegroundColor Cyan

# --------------------
# 1. Validate list file
# --------------------
if (-not (Test-Path $ListFile)) {
    Write-Host "[ERROR] List file not found: $ListFile" -ForegroundColor Red
    exit 1
}

$LogFiles = Get-Content $ListFile | Where-Object { $_.Trim() -ne "" }

if ($LogFiles.Count -eq 0) {
    Write-Host "[ERROR] The list file does not contain any log file paths." -ForegroundColor Red
    exit 1
}

# --------------------
# 2. Validate log files & store initial pointer
# --------------------
$ValidFiles = @{}
$ErrorsFound = $false

foreach ($Log in $LogFiles) {

    $Path = $Log.Trim()

    if (Test-Path $Path) {
        Write-Host "[OK] Watching: $Path" -ForegroundColor Green
        $InitialCount = (Get-Content $Path).Length
        $ValidFiles[$Path] = $InitialCount
    }
    else {
        Write-Host "[ERROR] File not found: $Path" -ForegroundColor Red
        $ErrorsFound = $true
    }
}

if ($ErrorsFound) {
    Write-Host "`nFix the missing files above before running again." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n--- Now watching logs. Press CTRL+C to stop ---`n" -ForegroundColor Cyan


# --------------------
# 3. Continuous watcher loop
# --------------------
try {
    while ($true) {
        foreach ($Log in @($ValidFiles.Keys)) {   # snapshot of keys to avoid modification exception
            $LastRead = $ValidFiles[$Log]

            if (-not (Test-Path $Log)) {
                Write-Host "[WARN] File disappeared: $Log" -ForegroundColor Yellow
                continue
            }

            $Lines = Get-Content -Path $Log -ErrorAction SilentlyContinue
            if ($Lines.Count -gt $LastRead) {

                # Get only new lines
                $NewLines = $Lines[$LastRead..($Lines.Count - 1)]

                # Resolve short filename for printing
                $ShortName = Split-Path $Log -Leaf

                foreach ($Line in $NewLines) {

                    # Default colour
                    $Colour = "White"

                    # Severity-based colour selection
                    if ($Line -match "\bERROR\b")      { $Colour = "Red" }
                    elseif ($Line -match "\bCRITICAL\b"){ $Colour = "Magenta" }
                    elseif ($Line -match "\bWARN(ING)?\b") { $Colour = "Yellow" }
                    elseif ($Line -match "\bINFO\b")   { $Colour = "Green" }

                    # Print filename in severity colour, log line in default colour
                    Write-Host ("{0}`t" -f $ShortName) -ForegroundColor $Colour -NoNewline
                    Write-Host $Line
                }

                # Update file pointer
                $ValidFiles[$Log] = $Lines.Count
            }
        }

        Start-Sleep -Milliseconds 400
    }
}
catch {
    Write-Host "`n[EXCEPTION CAUGHT]" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`n--- FULL EXCEPTION DETAILS ---" -ForegroundColor DarkRed
    Write-Host $_.Exception.ToString()
    Write-Host "`nThe watcher stopped due to an error." -ForegroundColor Yellow
}