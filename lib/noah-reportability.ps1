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

function Show-NoahSettingsDialog {
    <#
    .SYNOPSIS
    Show NOAH Settings dialog for configuring exe path and refreshing models cache
    #>
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "NOAH Settings"
    $dialog.Width = 600
    $dialog.Height = 450
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    # === EXE Path Section ===
    $lblExePath = New-Object System.Windows.Forms.Label
    $lblExePath.Location = New-Object System.Drawing.Point(10, 15)
    $lblExePath.Size = New-Object System.Drawing.Size(560, 20)
    $lblExePath.Text = "NOAH Executable Path:"

    $txtExePath = New-Object System.Windows.Forms.TextBox
    $txtExePath.Location = New-Object System.Drawing.Point(10, 40)
    $txtExePath.Size = New-Object System.Drawing.Size(470, 25)
    $txtExePath.Text = [string]$Config.exePath
    $txtExePath.ReadOnly = $true

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "Browse..."
    $btnBrowse.Width = 90
    $btnBrowse.Location = New-Object System.Drawing.Point(490, 38)
    $btnBrowse.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "NOAH Client (NOAHClientCentralRegistry.exe)|NOAHClientCentralRegistry.exe|Executable (*.exe)|*.exe|All files (*.*)|*.*"
        $ofd.Title = "Select NOAHClientCentralRegistry.exe"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtExePath.Text = $ofd.FileName
        }
    })

    # === Output Format Section ===
    $lblOutput = New-Object System.Windows.Forms.Label
    $lblOutput.Location = New-Object System.Drawing.Point(10, 75)
    $lblOutput.Size = New-Object System.Drawing.Size(120, 20)
    $lblOutput.Text = "Output Format:"

    $cmbOutput = New-Object System.Windows.Forms.ComboBox
    $cmbOutput.Location = New-Object System.Drawing.Point(130, 72)
    $cmbOutput.Size = New-Object System.Drawing.Size(100, 25)
    $cmbOutput.DropDownStyle = "DropDownList"
    $cmbOutput.Items.AddRange(@("hl7", "xml"))
    $outputIdx = if ($Config.output -eq "xml") { 1 } else { 0 }
    $cmbOutput.SelectedIndex = $outputIdx

    # === Models Section ===
    $grpModels = New-Object System.Windows.Forms.GroupBox
    $grpModels.Text = "Cached Models"
    $grpModels.Location = New-Object System.Drawing.Point(10, 110)
    $grpModels.Size = New-Object System.Drawing.Size(565, 220)

    $lblLastUpdated = New-Object System.Windows.Forms.Label
    $lblLastUpdated.Location = New-Object System.Drawing.Point(10, 25)
    $lblLastUpdated.Size = New-Object System.Drawing.Size(400, 20)

    # Load cached models
    $cachedModels = Get-CachedNoahModels
    if ($cachedModels -and $cachedModels.lastUpdated) {
        try {
            $lastUpdatedDate = [DateTime]::Parse($cachedModels.lastUpdated)
            $lblLastUpdated.Text = "Last updated: $($lastUpdatedDate.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        catch {
            $lblLastUpdated.Text = "Last updated: $($cachedModels.lastUpdated)"
        }
    }
    else {
        $lblLastUpdated.Text = "Last updated: Never (no cached models)"
    }

    $lstModels = New-Object System.Windows.Forms.ListBox
    $lstModels.Location = New-Object System.Drawing.Point(10, 50)
    $lstModels.Size = New-Object System.Drawing.Size(540, 120)
    $lstModels.Font = New-Object System.Drawing.Font("Consolas", 9)

    if ($cachedModels -and $cachedModels.models -and $cachedModels.models.Count -gt 0) {
        foreach ($model in $cachedModels.models) {
            $lstModels.Items.Add("$($model.name) - $($model.id)")
        }
    }
    else {
        $lstModels.Items.Add("(No models cached - click Refresh to fetch from API)")
    }

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh Models from API"
    $btnRefresh.Width = 180
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 180)

    $lblRefreshStatus = New-Object System.Windows.Forms.Label
    $lblRefreshStatus.Location = New-Object System.Drawing.Point(200, 183)
    $lblRefreshStatus.Size = New-Object System.Drawing.Size(350, 20)
    $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Blue

    $grpModels.Controls.AddRange(@($lblLastUpdated, $lstModels, $btnRefresh, $lblRefreshStatus))

    # Refresh button click handler
    $btnRefresh.Add_Click({
        # Validate exe path first
        $exePath = $txtExePath.Text
        if ([string]::IsNullOrWhiteSpace($exePath) -or -not (Test-Path -LiteralPath $exePath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please configure the NOAH executable path first.",
                "NOAH Settings",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $btnRefresh.Enabled = $false
        $lblRefreshStatus.Text = "Starting NOAH server..."
        $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Blue
        $dialog.Refresh()

        $serverProcess = $null
        try {
            # Create a temporary config with the current exe path
            $tempConfig = @{
                exePath = $exePath
                apiServerUrl = $Config.apiServerUrl
            }

            # Start the server
            $serverResult = Start-NoahServer -Config $tempConfig
            if (-not $serverResult.Success) {
                $lblRefreshStatus.Text = "Failed: $($serverResult.Message)"
                $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Red
                return
            }

            $serverProcess = $serverResult.Process
            $lblRefreshStatus.Text = "Fetching models from API..."
            $dialog.Refresh()

            # Fetch models
            $apiServerUrl = [string]$Config.apiServerUrl
            if ([string]::IsNullOrWhiteSpace($apiServerUrl)) {
                $apiServerUrl = "http://localhost:4000"
            }
            $apiServerUrl = $apiServerUrl.TrimEnd('/')

            $headers = @{
                "accept" = "*/*"
                "api-version" = "2"
            }

            $models = Invoke-RestMethod -Uri "$apiServerUrl/Models" -Method Get -Headers $headers -ErrorAction Stop

            if ($null -eq $models -or $models.Count -eq 0) {
                $lblRefreshStatus.Text = "No models returned from API"
                $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Orange
                return
            }

            # Save to cache
            Save-CachedNoahModels -Models $models

            # Update UI
            $lstModels.Items.Clear()
            foreach ($model in $models) {
                $lstModels.Items.Add("$($model.name) - $($model.id)")
            }
            $lblLastUpdated.Text = "Last updated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
            $lblRefreshStatus.Text = "Successfully loaded $($models.Count) model(s)"
            $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Green
        }
        catch {
            $lblRefreshStatus.Text = "Error: $($_.Exception.Message)"
            $lblRefreshStatus.ForeColor = [System.Drawing.Color]::Red
        }
        finally {
            # Always stop the server if we started it
            if ($null -ne $serverProcess) {
                Stop-NoahServer -Process $serverProcess
            }
            $btnRefresh.Enabled = $true
        }
    })

    # === Buttons ===
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Width = 100
    $btnSave.Location = New-Object System.Drawing.Point(380, 370)
    $btnSave.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(490, 370)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblExePath, $txtExePath, $btnBrowse, $lblOutput, $cmbOutput, $grpModels, $btnSave, $btnCancel))
    $dialog.AcceptButton = $btnSave
    $dialog.CancelButton = $btnCancel

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        # Save config changes
        $Config.exePath = $txtExePath.Text
        $Config.output = $cmbOutput.SelectedItem.ToString()
        Save-NoahConfig -Config $Config
        return $true
    }

    return $false
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
        $testResponse = Invoke-RestMethod -Uri "$apiServerUrl/Models" -Method Get -Headers $headers -TimeoutSec 2 -ErrorAction Stop
        return @{ Success = $true; Message = "Server is already running."; Process = $null }
    }
    catch {
        # Server not running, need to start it
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
                $testResponse = Invoke-RestMethod -Uri "$apiServerUrl/Models" -Method Get -Headers $headers -TimeoutSec 2 -ErrorAction Stop
                return @{ Success = $true; Message = "Server started successfully."; Process = $proc }
            }
            catch {
                # Server not ready yet, keep waiting
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

function Show-NoahModelSelectionDialog {
    <#
    .SYNOPSIS
    Show model selection dialog using cached models (no server required)
    
    .DESCRIPTION
    Loads models from config/models.json cache. If cache is empty,
    prompts user to go to Settings to refresh models from API.
    #>
    param(
        [Parameter(Mandatory=$true)]$Config
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Load cached models
    $cachedModels = Get-CachedNoahModels
    $models = @()
    if ($cachedModels -and $cachedModels.models -and $cachedModels.models.Count -gt 0) {
        $models = $cachedModels.models
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "NOAH Model Selection"
    $dialog.Width = 500
    $dialog.Height = 180
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

    # Status label
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(10, 75)
    $lblStatus.Size = New-Object System.Drawing.Size(460, 35)

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Run Filter"
    $btnOk.Width = 100
    $btnOk.Location = New-Object System.Drawing.Point(280, 115)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(390, 115)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblModel, $cmbModel, $lblStatus, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    # Check if we have cached models
    if ($models.Count -eq 0) {
        $cmbModel.Enabled = $false
        $btnOk.Enabled = $false
        $lblStatus.Text = "No cached models. Go to NOAH > Settings to refresh models from API."
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        
        $dialog.ShowDialog() | Out-Null
        return $null
    }

    # Populate model ComboBox
    foreach ($model in $models) {
        $displayText = "$($model.name) ($($model.id))"
        $cmbModel.Items.Add($displayText)
    }

    # Select first item or previously used model
    $selectedIdx = 0
    if (-not [string]::IsNullOrWhiteSpace($Config.modelId)) {
        for ($i = 0; $i -lt $models.Count; $i++) {
            if ($models[$i].id -eq $Config.modelId) {
                $selectedIdx = $i
                break
            }
        }
    }
    $cmbModel.SelectedIndex = $selectedIdx

    # Show output format info (uses config setting)
    $outputFormat = if ($Config.output -eq "xml") { "XML" } else { "HL7" }
    $lblStatus.Text = "Output format: $outputFormat (change in Settings)"
    $lblStatus.ForeColor = [System.Drawing.Color]::Gray

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedModelIndex = $cmbModel.SelectedIndex
        if ($selectedModelIndex -ge 0 -and $selectedModelIndex -lt $models.Count) {
            $selectedModel = $models[$selectedModelIndex]
            
            # Save selected model to config for next time
            $Config.modelId = $selectedModel.id
            Save-NoahConfig -Config $Config
            
            return @{
                ModelId = $selectedModel.id
                ModelName = $selectedModel.name
                OutputFormat = $Config.output
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
    catch { }

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
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                $errorDetails += "`nResponse: $responseBody"
            }
            catch {
                # Ignore errors reading response stream
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
