function Get-NoahConfigPath {
    return (Join-Path $PSScriptRoot "noah-config.json")
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
        }
    }

    return [pscustomobject]@{
        exePath = ""
        modelId = ""
        output  = "hl7"   # "hl7" or "xml"
        separateImpossiblesAndMets = $false
        workingRoot = ""  # if empty, uses $env:TEMP
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

function Resolve-NoahExePath {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    if ($Config.exePath -and (Test-Path -LiteralPath $Config.exePath)) {
        return $Config.exePath
    }

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NOAH Client (NOAHClientCentralRegistry.exe)|NOAHClientCentralRegistry.exe|Executable (*.exe)|*.exe|All files (*.*)|*.*"
    $ofd.Title  = "Select NOAHClientCentralRegistry.exe"

    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $Config.exePath = $ofd.FileName
    Save-NoahConfig -Config $Config
    return $Config.exePath
}

function Resolve-NoahModelId {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }

    $current = [string]$Config.modelId
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $tmp = [guid]::Empty
        if ([guid]::TryParse($current, [ref]$tmp)) {
            return $current
        }
    }

    $input = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter the NOAH model id (GUID).`nYou can copy this from the NOAH GUI (Update NLP Models).",
        "NOAH Model ID",
        $current
    )

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $null
    }

    $g = [guid]::Empty
    if (-not [guid]::TryParse($input.Trim(), [ref]$g)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Model id must be a GUID. You entered:`n$input",
            "Invalid Model ID",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $null
    }

    $Config.modelId = $g.ToString()
    Save-NoahConfig -Config $Config
    return $Config.modelId
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

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId
}

function Invoke-NoahReportabilityFilterForMessage {
    param(
        [Parameter(Mandatory=$true)][int]$MessageIndex,
        [Parameter(Mandatory=$true)][array]$Hl7Messages,
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

    # Create a copy of the "single HL7 message" in the temp source folder.
    $inputFileName = "message_{0}.hl7" -f ($MessageIndex + 1)
    $inputPath     = Join-Path $folders.source $inputFileName

    $exportResult = Export-SelectedHl7 -MessageIndex $MessageIndex -Hl7Messages $Hl7Messages -OutputPath $inputPath
    if (-not $exportResult.Success) {
        return @{
            Success = $false
            Message = "Failed to export HL7 message for NOAH."
            Errors  = $exportResult.Errors
            WorkingFolder = $folders.base
        }
    }

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId
}

function Invoke-NoahReportabilityFilter {
    param(
        [Parameter(Mandatory=$true)][string]$InputPath,
        [Parameter(Mandatory=$true)]$Folders,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ExePath,
        [Parameter(Mandatory=$true)][string]$ModelId
    )

    $output = ([string]$Config.output).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    $args = @(
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
        $args += "separateimpossiblesandmets=true"
    }

    $exeDir = Split-Path -Parent $ExePath
    $stdoutPath = Join-Path $Folders.base "noah_stdout.txt"
    $stderrPath = Join-Path $Folders.base "noah_stderr.txt"

    try {
        # Write arguments to a debug file for troubleshooting
        $argsDebugPath = Join-Path $Folders.base "noah_args.txt"
        $argsString = $args -join " "
        Set-Content -Path $argsDebugPath -Value $argsString -ErrorAction SilentlyContinue
        
        $proc = Start-Process `
            -FilePath $ExePath `
            -WorkingDirectory $exeDir `
            -ArgumentList $args `
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
                Args = $args
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
                Args = $args
                StdoutPath = $stdoutPath
                StderrPath = $stderrPath
                StdoutContent = $stdoutContent
                StderrContent = $stderrContent
            }
        }
        
        $timeoutMs = 10000
        $exited = $proc.WaitForExit($timeoutMs)
            
        if (-not $exited) {
            try { $proc.Kill() } catch {}
            return @{
                Success = $false
                Message = "NOAH did not exit within $($timeoutMs / 1000) seconds"
                WorkingFolder = $Folders.base
                Args = $args
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
            Args = $args
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
        Args = $args
        ExePath = $ExePath
        InputPath = $InputPath
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        WorkingDirectory = $exeDir
    }
}
