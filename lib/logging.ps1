$script:LogPath = $null
$script:LogMutex = $null

function Initialize-ParatLogging {
    $logDir = Join-Path $PSScriptRoot "..\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Single daily log file for all users
    $date = Get-Date -Format "yyyyMMdd"
    $script:LogPath = Join-Path $logDir "parat_${date}.log"

    # Create named mutex for cross-process coordination
    $script:LogMutex = New-Object System.Threading.Mutex($false, "Global\ParatLogMutex")

    Write-ParatLog -Level INFO -Message "Session started" -Action "STARTUP"
}

function Write-ParatLog {
    param(
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [string]$Message,
        [string]$Action,        # e.g., "OPEN_FILE", "NOAH_API", "EXPORT"
        [string]$ErrorDetails   # Stack trace for errors (sanitized)
    )

    if (-not $script:LogPath) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $userInfo = "$env:COMPUTERNAME\$env:USERNAME"
    $entry = "[$timestamp] [$userInfo] [$Level] [$Action] $Message"
    if ($ErrorDetails) {
        $entry += "`n  Error: $ErrorDetails"
    }

    # Acquire mutex before writing (100ms timeout)
    $acquired = $false
    try {
        $acquired = $script:LogMutex.WaitOne(100)
        if ($acquired) {
            Add-Content -Path $script:LogPath -Value $entry -ErrorAction Stop
        } else {
            # Mutex busy - write to local fallback
            $fallback = Join-Path $env:TEMP "parat_log_fallback.txt"
            Add-Content -Path $fallback -Value $entry -ErrorAction SilentlyContinue
        }
    } catch {
        # Silent fail - don't crash app for logging failure
        $null = $_.Exception
    } finally {
        if ($acquired) {
            $script:LogMutex.ReleaseMutex()
        }
    }
}

function Close-ParatLogging {
    Write-ParatLog -Level INFO -Message "Session ended" -Action "SHUTDOWN"
    if ($script:LogMutex) {
        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }
}

function Write-ParatError {
    param(
        [string]$Message,
        [string]$Action,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    # Sanitize error - remove any potential PHI from file paths/data
    $sanitizedError = $ErrorRecord.Exception.Message
    $sanitizedError = $sanitizedError -replace '\b\d{3}-\d{2}-\d{4}\b', '[SSN]'
    $sanitizedError = $sanitizedError -replace '\b\d{9}\b', '[MRN]'

    Write-ParatLog -Level ERROR -Message $Message -Action $Action -ErrorDetails $sanitizedError
}
