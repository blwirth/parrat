function Get-NoahConfigPath {
    $root = Split-Path -Parent $PSScriptRoot
    return [System.IO.Path]::Combine($root, "config", "noah-config.json")
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

function Get-NoahModels {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    $apiServerUrl = [string]$Config.apiServerUrl
    if ([string]::IsNullOrWhiteSpace($apiServerUrl)) {
        $apiServerUrl = "http://localhost:4000"
    }

    # Ensure URL doesn't end with a slash
    $apiServerUrl = $apiServerUrl.TrimEnd('/')

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

function Show-NoahModelSelectionDialog {
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "NOAH Model Selection"
    $dialog.Width = 500
    $dialog.Height = 250
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    # Label for model selection
    $lblModel = New-Object System.Windows.Forms.Label
    $lblModel.Location = New-Object System.Drawing.Point(10, 15)
    $lblModel.Size = New-Object System.Drawing.Size(460, 20)
    $lblModel.Text = "Select Model:"

    # ComboBox for model selection
    $cmbModel = New-Object System.Windows.Forms.ComboBox
    $cmbModel.Location = New-Object System.Drawing.Point(10, 40)
    $cmbModel.Size = New-Object System.Drawing.Size(460, 25)
    $cmbModel.DropDownStyle = "DropDownList"
    $cmbModel.Enabled = $false

    # Label for output format
    $lblOutput = New-Object System.Windows.Forms.Label
    $lblOutput.Location = New-Object System.Drawing.Point(10, 80)
    $lblOutput.Size = New-Object System.Drawing.Size(460, 20)
    $lblOutput.Text = "Output Format:"

    # ComboBox for output format
    $cmbOutput = New-Object System.Windows.Forms.ComboBox
    $cmbOutput.Location = New-Object System.Drawing.Point(10, 105)
    $cmbOutput.Size = New-Object System.Drawing.Size(460, 25)
    $cmbOutput.DropDownStyle = "DropDownList"
    $cmbOutput.Items.AddRange(@("HL7", "XML"))
    $cmbOutput.SelectedIndex = 0

    # Status label
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(10, 140)
    $lblStatus.Size = New-Object System.Drawing.Size(460, 20)
    $lblStatus.Text = "Loading models..."
    $lblStatus.ForeColor = [System.Drawing.Color]::Blue

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Width = 100
    $btnOk.Location = New-Object System.Drawing.Point(280, 170)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Enabled = $false

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(390, 170)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblModel, $cmbModel, $lblOutput, $cmbOutput, $lblStatus, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    # Fetch models asynchronously (using a simple approach)
    $models = Get-NoahModels -Config $Config

    if ($null -eq $models -or $models.Count -eq 0) {
        $lblStatus.Text = "Failed to load models. Please check the API server URL."
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        
        $dialogResult = $dialog.ShowDialog()
        return $null
    }

    # Populate model ComboBox
    foreach ($model in $models) {
        $displayText = "$($model.name) ($($model.id))"
        $cmbModel.Items.Add($displayText)
    }

    if ($cmbModel.Items.Count -gt 0) {
        $cmbModel.SelectedIndex = 0
        $cmbModel.Enabled = $true
        $btnOk.Enabled = $true
        $lblStatus.Text = "Select a model and output format, then click OK."
        $lblStatus.ForeColor = [System.Drawing.Color]::Black
    }
    else {
        $lblStatus.Text = "No models available."
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
    }

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedModelIndex = $cmbModel.SelectedIndex
        if ($selectedModelIndex -ge 0 -and $selectedModelIndex -lt $models.Count) {
            $selectedModel = $models[$selectedModelIndex]
            $selectedOutput = $cmbOutput.SelectedItem.ToString().ToLowerInvariant()
            
            return @{
                ModelId = $selectedModel.id
                OutputFormat = $selectedOutput
            }
        }
    }

    return $null
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

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId -OutputFormat $output
}

function Invoke-NoahReportabilityFilterForMessage {
    param(
        [Parameter(Mandatory=$true)][int]$MessageIndex,
        [Parameter(Mandatory=$true)][array]$Hl7Messages,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$OutputFormat
    )

    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) { return @{ Success = $false; Message = "NOAH exe not selected." } }

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return @{ Success = $false; Message = "NOAH model id not provided." }
    }

    $output = ([string]$OutputFormat).ToLowerInvariant()
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

    $exportResult = Export-SelectedHl7 -MessageIndices @($MessageIndex) -Hl7Messages $Hl7Messages -OutputPath $inputPath
    if (-not $exportResult.Success) {
        return @{
            Success = $false
            Message = "Failed to export HL7 message for NOAH."
            Errors  = $exportResult.Errors
            WorkingFolder = $folders.base
        }
    }

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId -OutputFormat $output
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

function Show-CustomPayloadDialog {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "NOAH Custom Payload"
    $dialog.Width = 600
    $dialog.Height = 400
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(400, 300)

    # Label
    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
    $lblPrompt.Size = New-Object System.Drawing.Size(560, 40)
    $lblPrompt.Text = "Enter the text you want to test against NOAH reportability:`n(This will be placed in the FinalDiagnosis OBX segment)"

    # Text box
    $txtCustomText = New-Object System.Windows.Forms.TextBox
    $txtCustomText.Location = New-Object System.Drawing.Point(10, 55)
    $txtCustomText.Size = New-Object System.Drawing.Size(560, 250)
    $txtCustomText.Multiline = $true
    $txtCustomText.ScrollBars = "Vertical"
    $txtCustomText.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtCustomText.Anchor = "Top,Left,Right,Bottom"

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Test with NOAH"
    $btnOk.Width = 120
    $btnOk.Location = New-Object System.Drawing.Point(350, 315)
    $btnOk.Anchor = "Bottom,Right"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(480, 315)
    $btnCancel.Anchor = "Bottom,Right"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblPrompt, $txtCustomText, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $text = $txtCustomText.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    return $null
}

function Invoke-NoahReportabilityFilterForCustomPayload {
    param(
        [Parameter(Mandatory=$true)][string]$CustomText,
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$OutputFormat
    )

    $exePath = Resolve-NoahExePath -Config $Config
    if (-not $exePath) { return @{ Success = $false; Message = "NOAH exe not selected." } }

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return @{ Success = $false; Message = "NOAH model id not provided." }
    }

    $output = ([string]$OutputFormat).ToLowerInvariant()
    if ($output -ne "hl7" -and $output -ne "xml") { $output = "hl7" }

    $workingRoot = [string]$Config.workingRoot
    if ([string]::IsNullOrWhiteSpace($workingRoot)) { $workingRoot = $env:TEMP }
    if (-not (Test-Path -LiteralPath $workingRoot)) {
        $workingRoot = $env:TEMP
    }

    $folders = New-NoahWorkingFolders -OutputFormat $output -WorkingRoot $workingRoot

    # Generate minimal HL7 message with custom text
    $hl7Content = New-MinimalHl7Message -CustomText $CustomText

    # Save to source folder
    $inputFileName = "custom_payload.hl7"
    $inputPath = Join-Path $folders.source $inputFileName

    try {
        Set-Content -LiteralPath $inputPath -Value $hl7Content -Encoding ASCII -NoNewline
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to write custom HL7 payload: $($_.Exception.Message)"
            WorkingFolder = $folders.base
        }
    }

    return Invoke-NoahReportabilityFilter -InputPath $inputPath -Folders $folders -Config $Config -ExePath $exePath -ModelId $modelId -OutputFormat $output
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
        
        $timeoutMs = 15000
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
