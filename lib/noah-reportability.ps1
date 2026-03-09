function Get-NoahConfigPath {
    $root = Split-Path -Parent $PSScriptRoot
    return [System.IO.Path]::Combine($root, "config", "noah-config.json")
}

function Get-NoahModelsPath {
    $root = Split-Path -Parent $PSScriptRoot
    return [System.IO.Path]::Combine($root, "config", "models.json")
}

function Get-CachedNoahModels {
    <#
    .SYNOPSIS
    Load cached NOAH models from config/models.json

    .OUTPUTS
    PSCustomObject with lastUpdated and models properties, or null if cache doesn't exist/is invalid
    #>
    $modelsPath = Get-NoahModelsPath
    if (-not (Test-Path -LiteralPath $modelsPath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $modelsPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        $cache = $raw | ConvertFrom-Json
        return $cache
    }
    catch {
        return $null
    }
}

function Save-CachedNoahModels {
    <#
    .SYNOPSIS
    Save NOAH models to config/models.json cache

    .PARAMETER Models
    Array of model objects with id and name properties
    #>
    param(
        [Parameter(Mandatory=$true)][array]$Models
    )

    $modelsPath = Get-NoahModelsPath
    $cache = @{
        lastUpdated = (Get-Date).ToString("o")
        models = $Models
    }

    $json = $cache | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $modelsPath -Value $json -Encoding UTF8
}

function Get-NoahConfig {
    $configPath = Get-NoahConfigPath
    if (Test-Path -LiteralPath $configPath) {
        try {
            $raw = Get-Content -LiteralPath $configPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                return ($raw | ConvertFrom-Json)
            }
        }
        catch {
            # ignore and fall back to defaults
            $null = $_.Exception
        }
    }

    return [pscustomobject]@{
        exePath = ""
        modelId = ""
        output  = "hl7"   # "hl7" or "xml"
        separateImpossiblesAndMets = $false
        workingRoot = ""  # if empty, uses $env:TEMP
        apiServerUrl = "http://localhost:4000"
    }
}

function Save-NoahConfig {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    $configPath = Get-NoahConfigPath
    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $configPath -Value $json -Encoding UTF8
}

function Start-NoahServer {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) {
        return @{ Success = $false; Message = "NOAH exe path not configured."; Process = $null }
    }

    $apiServerUrl = [string]$Config.apiServerUrl
    if ([string]::IsNullOrWhiteSpace($apiServerUrl)) {
        $apiServerUrl = "http://localhost:4000"
    }
    $apiServerUrl = $apiServerUrl.TrimEnd('/')

    # Check if server is already running
    try {
        $headers = @{
            "accept" = "*/*"
            "api-version" = "2"
        }
        $null = Invoke-RestMethod -Uri "$apiServerUrl/Models" -Method Get -Headers $headers -TimeoutSec 2 -ErrorAction Stop
        return @{ Success = $true; Message = "Server is already running."; Process = $null }
    }
    catch {
        # Server not running, need to start it
        $null = $_.Exception
    }

    # Start the server process
    $exeDir = Split-Path -Parent $exePath

    try {
        # Start server process (may need specific arguments - adjust as needed)
        $proc = Start-Process `
            -FilePath $exePath `
            -WorkingDirectory $exeDir `
            -WindowStyle Minimized `
            -PassThru `
            -ErrorAction Stop

        if (-not $proc) {
            return @{ Success = $false; Message = "Failed to start NOAH server process."; Process = $null }
        }

        # Wait for server to be ready (polling with timeout)
        $maxWaitSeconds = 30
        $checkIntervalMs = 500
        $maxAttempts = ($maxWaitSeconds * 1000) / $checkIntervalMs
        $attempt = 0

        while ($attempt -lt $maxAttempts) {
            Start-Sleep -Milliseconds $checkIntervalMs
            try {
                $headers = @{
                    "accept" = "*/*"
                    "api-version" = "2"
                }
                $null = Invoke-RestMethod -Uri "$apiServerUrl/Models" -Method Get -Headers $headers -TimeoutSec 2 -ErrorAction Stop
                return @{ Success = $true; Message = "Server started successfully."; Process = $proc }
            }
            catch {
                # Server not ready yet, keep waiting
                $null = $_.Exception
            }
            $attempt++
        }

        # Server didn't become ready - but process might still be running
        return @{ Success = $false; Message = "Server started but did not become ready within $maxWaitSeconds seconds."; Process = $proc }
    }
    catch {
        return @{ Success = $false; Message = "Failed to start NOAH server: $($_.Exception.Message)"; Process = $null }
    }
}

function Stop-NoahServer {
    param(
        [System.Diagnostics.Process]$Process
    )

    if ($null -eq $Process) {
        return
    }

    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
            $Process.WaitForExit(5000)
        }
    }
    catch {
        # Ignore errors when stopping
        $null = $_.Exception
    }
}

function Get-NoahModels {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$false)][ref]$ServerProcess
    )

    $apiServerUrl = [string]$Config.apiServerUrl
    if ([string]::IsNullOrWhiteSpace($apiServerUrl)) {
        $apiServerUrl = "http://localhost:4000"
    }

    # Ensure URL doesn't end with a slash
    $apiServerUrl = $apiServerUrl.TrimEnd('/')

    # Start server if not running
    $serverResult = Start-NoahServer -Config $Config
    if (-not $serverResult.Success) {
        Write-Error "Failed to start NOAH server: $($serverResult.Message)"
        return $null
    }

    # Store process reference if server was started
    if ($null -ne $ServerProcess) {
        $ServerProcess.Value = $serverResult.Process
    }

    $modelsUrl = "$apiServerUrl/Models"

    try {
        $headers = @{
            "accept" = "*/*"
            "api-version" = "2"
        }

        $response = Invoke-RestMethod -Uri $modelsUrl -Method Get -Headers $headers -ErrorAction Stop
        return $response
    }
    catch {
        Write-Error "Failed to fetch NOAH models from $modelsUrl : $($_.Exception.Message)"
        return $null
    }
}

function New-NoahWorkingFolders {
    param(
        [Parameter(Mandatory=$true)][string]$OutputFormat,
        [Parameter(Mandatory=$true)][string]$WorkingRoot
    )

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $runId = [guid]::NewGuid().ToString()
    $base  = Join-Path $WorkingRoot ("noah_reportability_{0}_{1}" -f $stamp, $runId)

    $folders = [ordered]@{
        base          = $base
        source        = (Join-Path $base "source")
        reportable    = (Join-Path $base "reportable")
        nonreportable = (Join-Path $base "nonreportable")
        reports       = (Join-Path $base "reports")
        outputFormat  = $OutputFormat
    }

    foreach ($p in @($folders.base, $folders.source, $folders.reportable, $folders.nonreportable, $folders.reports)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }

    return [pscustomobject]$folders
}

function Invoke-NoahReportabilityFilterForTumor {
    param(
        [Parameter(Mandatory=$true)][int]$TumorIndex,
        [Parameter(Mandatory=$true)][System.Xml.XmlDocument]$XmlDoc,
        [Parameter(Mandatory=$true)][System.Xml.XmlNamespaceManager]$NsMgr,
        [Parameter(Mandatory=$true)]$Config
    )

    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) { return @{ Success = $false; Message = "NOAH exe not selected." } }

    $modelId = Resolve-NoahModelId -Config $Config
    if (-not $modelId) { return @{ Success = $false; Message = "NOAH model id not provided." } }

    $output = ([string]$Config.output).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    $workingRoot = [string]$Config.workingRoot
    if ([string]::IsNullOrWhiteSpace($workingRoot)) { $workingRoot = $env:TEMP }
    if (-not (Test-Path -LiteralPath $workingRoot)) {
        $workingRoot = $env:TEMP
    }

    $folders = New-NoahWorkingFolders -OutputFormat $output -WorkingRoot $workingRoot

    # Create a copy of the "single tumor" NAACCR XML payload in the temp source folder.
    $inputFileName = "tumor_{0}.xml" -f ($TumorIndex + 1)
    $inputPath     = Join-Path $folders.source $inputFileName

    $exportResult = Export-SelectedXml -TumorIndices @($TumorIndex) -XmlDoc $XmlDoc -NsMgr $NsMgr -OutputPath $inputPath
    if (-not $exportResult.Success) {
        return @{
            Success = $false
            Message = "Failed to export tumor XML for NOAH."
            Errors  = $exportResult.Errors
            WorkingFolder = $folders.base
        }
    }

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId -OutputFormat $output
}

function Invoke-NoahReportabilityApi {
    param(
        [Parameter(Mandatory=$true)][string]$Hl7Message,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$false)][string]$MessageId = $null,
        [Parameter(Mandatory=$false)][System.Diagnostics.Process]$ServerProcess = $null
    )

    $apiServerUrl = [string]$Config.apiServerUrl
    if ([string]::IsNullOrWhiteSpace($apiServerUrl)) {
        $apiServerUrl = "http://localhost:4000"
    }
    $apiServerUrl = $apiServerUrl.TrimEnd('/')

    if ([string]::IsNullOrWhiteSpace($MessageId)) {
        $MessageId = [guid]::NewGuid().ToString()
    }

    # Ensure ModelId is a valid GUID format
    $guid = [guid]::Empty
    if (-not [guid]::TryParse($ModelId, [ref]$guid)) {
        return @{
            Success = $false
            Message = "Invalid ModelId format: $ModelId (must be a GUID)"
        }
    }
    $ModelId = $guid.ToString()

    # Encode HL7 message as Base64
    # HL7 uses ASCII/UTF-8, but preserve exact bytes
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Hl7Message)
    $hl7MessageEncoded = [System.Convert]::ToBase64String($bytes)

    # Build request body - array of objects wrapped in "value" property
    $requestObj = @{
        messageId = $MessageId
        hl7Message = $hl7MessageEncoded
        messageEncodingFormat = "Base64"
        modelId = $ModelId
    }

    # Wrap array in "value" property as required by the API
    $requestBodyObj = @{
        value = @($requestObj)
    }

    $requestBody = $requestBodyObj | ConvertTo-Json -Depth 10 -Compress

    $endpoint = "$apiServerUrl/api/NER"

    # Debug: Write request to temp file for inspection
    $debugFile = Join-Path $env:TEMP "noah_api_request_debug.json"
    try {
        $requestBodyObj | ConvertTo-Json -Depth 10 | Set-Content -Path $debugFile -ErrorAction SilentlyContinue
    }
    catch { $null = $_.Exception }

    try {
        $headers = @{
            "Content-Type" = "application/json"
            "Accept" = "application/json"
            "api-version" = "2"
        }

        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $requestBody -ErrorAction Stop

        # Stop server after successful POST
        if ($null -ne $ServerProcess) {
            Stop-NoahServer -Process $ServerProcess
        }

        if ($null -eq $response -or $response.Count -eq 0) {
            return @{
                Success = $false
                Message = "NOAH API returned empty response"
            }
        }

        # Get the first result (since we only sent one message)
        $result = $response[0]

        # Convert reportable string to boolean
        $isReportable = $result.reportable -eq "true"
        $isNonReportable = $result.reportable -eq "false"

        # Determine classification
        $classification = "unknown"
        if ($isReportable) {
            $classification = "reportable"
        }
        elseif ($isNonReportable) {
            $classification = "nonreportable"
        }

        return @{
            Success = $true
            Classification = $classification
            Reportable = $isReportable
            ImpossibleCombination = $result.impossibleCombination -eq "true"
            MetastaticReport = $result.metastaticReport -eq $true
            MessageId = $result.messageId
            ApiResponse = $result
        }
    }
    catch {
        # Stop server even on error
        if ($null -ne $ServerProcess) {
            Stop-NoahServer -Process $ServerProcess
        }

        $errorDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            $reader = $null
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $errorDetails += "`nResponse: $responseBody"
            }
            catch {
                # Ignore errors reading response stream
                $null = $_.Exception
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
            }
        }

        return @{
            Success = $false
            Message = "Failed to POST to NOAH API: $errorDetails"
            Exception = $_.Exception
            RequestBody = $requestBody
            DebugFile = $debugFile
        }
    }
}

function Invoke-NoahReportabilityFilterForMessage {
    <#
    .SYNOPSIS
    Run NOAH reportability filter on an HL7 message using CLI

    .DESCRIPTION
    Uses NOAHClientCentralRegistry.exe CLI to process the HL7 message.
    Creates temp folders, writes HL7 to file, runs CLI, and returns results.
    #>
    param(
        [Parameter(Mandatory=$true)][int]$MessageIndex,
        [Parameter(Mandatory=$true)][array]$Hl7Messages,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$OutputFormat
    )

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return @{ Success = $false; Message = "NOAH model id not provided." }
    }

    # Resolve exe path
    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) {
        return @{ Success = $false; Message = "NOAH exe not selected." }
    }

    # Get output format from config if not specified
    $output = ([string]$OutputFormat).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    # Determine working root
    $workingRoot = [string]$Config.workingRoot
    if ([string]::IsNullOrWhiteSpace($workingRoot)) { $workingRoot = $env:TEMP }
    if (-not (Test-Path -LiteralPath $workingRoot)) {
        $workingRoot = $env:TEMP
    }

    # Create working folders
    $folders = New-NoahWorkingFolders -OutputFormat $output -WorkingRoot $workingRoot

    # Get the HL7 message content and write to temp file
    $hl7Message = $Hl7Messages[$MessageIndex].RawContent
    $inputFileName = "message_{0}.hl7" -f ($MessageIndex + 1)
    $inputPath = Join-Path $folders.source $inputFileName

    try {
        # Write HL7 message to file - use ASCII encoding for HL7
        Set-Content -LiteralPath $inputPath -Value $hl7Message -Encoding ASCII -NoNewline
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to write HL7 message to temp file: $($_.Exception.Message)"
            WorkingFolder = $folders.base
        }
    }

    # Run CLI
    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $ModelId -OutputFormat $output
}

function New-MinimalHl7Message {
    param(
        [Parameter(Mandatory=$true)][string]$CustomText,
        [string]$PatientId = "TEST000001",
        [string]$AccessionNumber = "TEST-ACC-001"
    )

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $msgId = [guid]::NewGuid().ToString().Substring(0, 8)

    # HL7 segment separator is carriage return (0x0D)
    $segmentSeparator = "`r"

    # Build minimal HL7 ORU^R01 message
    $segments = @()

    # MSH - Message Header
    $segments += "MSH|^~\&|ePATH|TEST_FACILITY|NOAH|NOAH_FACILITY|$timestamp||ORU^R01|$msgId|P|2.5.1"

    # PID - Patient Identification
    $segments += "PID|1||$PatientId^^^TEST_FACILITY^MR||TEST^PATIENT||19700101|U"

    # OBR - Observation Request
    $segments += "OBR|1||$AccessionNumber||88305^Surgical Pathology|||$timestamp"

    # OBX - Observation/Result
    # OBX segment 2 corresponds to FinalDiagnosis in NOAH's mapping
    # Format: OBX|SequenceNum|DataType|ObservationID|SubID|Value|Units|RefRange|AbnormalFlags|Probability|NatureOfAbnormalTest|ObservationResultStatus
    $segments += "OBX|1|FT|88305&ICD10&2.16.840.1.113883.6.90^Final Diagnosis^L|2|$CustomText||||||F"

    # Join segments with carriage return
    $hl7Message = $segments -join $segmentSeparator

    return $hl7Message
}

function Invoke-NoahReportabilityFilterForCustomPayload {
    <#
    .SYNOPSIS
    Run NOAH reportability filter on custom text using CLI

    .DESCRIPTION
    Generates a minimal HL7 message with the custom text and processes via CLI.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$CustomText,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$OutputFormat
    )

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return @{ Success = $false; Message = "NOAH model id not provided." }
    }

    # Resolve exe path
    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) {
        return @{ Success = $false; Message = "NOAH exe not selected." }
    }

    # Get output format
    $output = ([string]$OutputFormat).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    # Determine working root
    $workingRoot = [string]$Config.workingRoot
    if ([string]::IsNullOrWhiteSpace($workingRoot)) { $workingRoot = $env:TEMP }
    if (-not (Test-Path -LiteralPath $workingRoot)) {
        $workingRoot = $env:TEMP
    }

    # Create working folders
    $folders = New-NoahWorkingFolders -OutputFormat $output -WorkingRoot $workingRoot

    # Generate minimal HL7 message with custom text
    $hl7Message = New-MinimalHl7Message -CustomText $CustomText
    $inputFileName = "custom_payload_{0}.hl7" -f [guid]::NewGuid().ToString().Substring(0, 8)
    $inputPath = Join-Path $folders.source $inputFileName

    try {
        # Write HL7 message to file - use ASCII encoding for HL7
        Set-Content -LiteralPath $inputPath -Value $hl7Message -Encoding ASCII -NoNewline
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to write HL7 message to temp file: $($_.Exception.Message)"
            WorkingFolder = $folders.base
        }
    }

    # Run CLI
    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $ModelId -OutputFormat $output
}

function Invoke-NoahReportabilityFilter {
    param(
        [Parameter(Mandatory=$true)][string]$InputPath,
        [Parameter(Mandatory=$true)]$Folders,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ExePath,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$OutputFormat
    )

    $output = ([string]$OutputFormat).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    $cliArgs = @(
        "action=filter",
        "mode=batch",
        ("source={0}" -f $Folders.source),
        ("reportable={0}" -f $Folders.reportable),
        ("nonreportable={0}" -f $Folders.nonreportable),
        ("report={0}" -f $Folders.reports),
        ("model={0}" -f $ModelId),
        ("output={0}" -f $output)
    )

    if ($Config.separateImpossiblesAndMets -eq $true) {
        $cliArgs += "separateimpossiblesandmets=true"
    }

    $exeDir = Split-Path -Parent $ExePath
    $stdoutPath = Join-Path $Folders.base "noah_stdout.txt"
    $stderrPath = Join-Path $Folders.base "noah_stderr.txt"

    try {
        # Write arguments to a debug file for troubleshooting
        $argsDebugPath = Join-Path $Folders.base "noah_args.txt"
        $argsString = $cliArgs -join " "
        Set-Content -Path $argsDebugPath -Value $argsString -ErrorAction SilentlyContinue

        $proc = Start-Process `
            -FilePath $ExePath `
            -WorkingDirectory $exeDir `
            -ArgumentList $cliArgs `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -ErrorAction Stop

        if (-not $proc) {
            return @{
                Success = $false
                Message = "Failed to start NOAH process (process object is null)"
                WorkingFolder = $Folders.base
                Args = $cliArgs
                StdoutPath = $stdoutPath
                StderrPath = $stderrPath
            }
        }

        # Give the process a moment to start
        Start-Sleep -Milliseconds 100

        # Check if process has already exited (indicates immediate failure)
        if ($proc.HasExited) {
            $exitCode = $proc.ExitCode
            $stdoutContent = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue } else { "" }
            $stderrContent = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue } else { "" }

            return @{
                Success = $false
                Message = "NOAH process exited immediately with code $exitCode"
                ExitCode = $exitCode
                WorkingFolder = $Folders.base
                Args = $cliArgs
                StdoutPath = $stdoutPath
                StderrPath = $stderrPath
                StdoutContent = $stdoutContent
                StderrContent = $stderrContent
            }
        }

        $timeoutMs = 15000
        $exited = $proc.WaitForExit($timeoutMs)

        if (-not $exited) {
            try { $proc.Kill() } catch { $null = $_.Exception }
            return @{
                Success = $false
                Message = "NOAH did not exit within $($timeoutMs / 1000) seconds"
                WorkingFolder = $Folders.base
                Args = $cliArgs
                StdoutPath = $stdoutPath
                StderrPath = $stderrPath
            }
        }

        $exitCode = $proc.ExitCode
    }
    catch {
        return @{
            Success = $false
            Message = "Failed running NOAH CLI: $($_.Exception.Message)"
            WorkingFolder = $Folders.base
            Args = $cliArgs
            ExePath = $ExePath
            WorkingDirectory = $exeDir
            ExceptionType = $_.Exception.GetType().FullName
        }
    }

    $reportableFiles    = @(Get-ChildItem -LiteralPath $Folders.reportable -Recurse -File -ErrorAction SilentlyContinue)
    $nonreportableFiles = @(Get-ChildItem -LiteralPath $Folders.nonreportable -Recurse -File -ErrorAction SilentlyContinue)

    $classification = "unknown"
    if ($reportableFiles.Count -gt 0 -and $nonreportableFiles.Count -eq 0) {
        $classification = "reportable"
    }
    elseif ($nonreportableFiles.Count -gt 0 -and $reportableFiles.Count -eq 0) {
        $classification = "nonreportable"
    }
    elseif ($nonreportableFiles.Count -gt 0 -and $reportableFiles.Count -gt 0) {
        $classification = "mixed"
    }

    return @{
        Success = $true
        ExitCode = $exitCode
        Classification = $classification
        WorkingFolder = $Folders.base
        ReportableCount = $reportableFiles.Count
        NonreportableCount = $nonreportableFiles.Count
        Args = $cliArgs
        ExePath = $ExePath
        InputPath = $InputPath
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        WorkingDirectory = $exeDir
    }
}
