# noah-reportability-ui.ps1
# UI dialogs for NOAH reportability features

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
    catch { $null = $_.Exception }

    $current = [string]$Config.modelId
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $tmp = [guid]::Empty
        if ([guid]::TryParse($current, [ref]$tmp)) {
            return $current
        }
    }

    $userInput = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter the NOAH model id (GUID).`nYou can copy this from the NOAH GUI (Update NLP Models).",
        "NOAH Model ID",
        $current
    )

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        return $null
    }

    $g = [guid]::Empty
    if (-not [guid]::TryParse($userInput.Trim(), [ref]$g)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Model id must be a GUID. You entered:`n$userInput",
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
