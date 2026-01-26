# obx-skip-config.ps1
# Configuration management for OBX skip codes used in site/laterality testing

function Get-ObxSkipConfigPath {
    <#
    .SYNOPSIS
    Returns the path to the OBX skip code configuration file
    #>
    return Join-Path $PSScriptRoot "..\config\obx-skip-config.json"
}

function Get-ObxSkipConfig {
    <#
    .SYNOPSIS
    Load OBX skip code configuration from file

    .OUTPUTS
    Hashtable with skipCodes array and skipCodeDescriptions hashtable
    #>

    $configPath = Get-ObxSkipConfigPath

    $defaultConfig = @{
        version = 1
        skipCodes = @("Gross Description", "Microscopic Description", "Clinical History")
        skipCodeDescriptions = @{
            "Gross Description" = "Gross Description"
            "Microscopic Description" = "Microscopic Description"
            "Clinical History" = "Clinical History"
        }
    }

    if (-not (Test-Path $configPath)) {
        return $defaultConfig
    }

    try {
        $json = Get-Content -Path $configPath -Raw | ConvertFrom-Json

        # Convert to hashtable
        $config = @{
            version = if ($json.version) { $json.version } else { 1 }
            skipCodes = @($json.skipCodes)
            skipCodeDescriptions = @{}
        }

        # Convert skipCodeDescriptions from PSObject to hashtable
        if ($json.skipCodeDescriptions) {
            $json.skipCodeDescriptions.PSObject.Properties | ForEach-Object {
                $config.skipCodeDescriptions[$_.Name] = $_.Value
            }
        }

        return $config
    }
    catch {
        Write-Warning "Failed to load OBX skip config: $($_.Exception.Message)"
        return $defaultConfig
    }
}

function Save-ObxSkipConfig {
    <#
    .SYNOPSIS
    Persist OBX skip code configuration to file

    .PARAMETER Config
    Hashtable containing skipCodes array and skipCodeDescriptions hashtable
    #>
    param(
        [Parameter(Mandatory=$true)][hashtable]$Config
    )

    $configPath = Get-ObxSkipConfigPath

    $configDir = Split-Path $configPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    try {
        $json = @{
            version = if ($Config.version) { $Config.version } else { 1 }
            skipCodes = @($Config.skipCodes)
            skipCodeDescriptions = $Config.skipCodeDescriptions
        }

        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
        return $true
    }
    catch {
        Write-Warning "Failed to save OBX skip config: $($_.Exception.Message)"
        return $false
    }
}

function Show-ObxSkipConfigDialog {
    <#
    .SYNOPSIS
    Show WinForms dialog to edit OBX skip codes

    .OUTPUTS
    $true if config was saved, $false otherwise
    #>

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $config = Get-ObxSkipConfig

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "OBX Skip Codes Configuration"
    $dialog.Width = 500
    $dialog.Height = 400
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Location = New-Object System.Drawing.Point(15, 15)
    $lblDesc.Size = New-Object System.Drawing.Size(455, 40)
    $lblDesc.Text = "Configure OBX-3.1 codes to skip when extracting text for site/laterality testing.`r`nOBX segments with these codes will be excluded from analysis."

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 60)
    $listView.Size = New-Object System.Drawing.Size(350, 230)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.MultiSelect = $false
    $listView.HideSelection = $false

    [void]$listView.Columns.Add("Code", 80)
    [void]$listView.Columns.Add("Description", 250)

    foreach ($code in $config.skipCodes) {
        $item = New-Object System.Windows.Forms.ListViewItem($code)
        $desc = if ($config.skipCodeDescriptions.ContainsKey($code)) { $config.skipCodeDescriptions[$code] } else { "" }
        [void]$item.SubItems.Add($desc)
        [void]$listView.Items.Add($item)
    }

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add..."
    $btnAdd.Width = 100
    $btnAdd.Location = New-Object System.Drawing.Point(375, 60)
    $btnAdd.Add_Click({
        $addResult = Show-AddSkipCodeDialog
        if ($null -ne $addResult) {
            # Check for duplicates
            $exists = $false
            foreach ($existing in $listView.Items) {
                if ($existing.Text -eq $addResult.Code) {
                    $exists = $true
                    break
                }
            }

            if ($exists) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Code '$($addResult.Code)' already exists.",
                    "Duplicate Code",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
            else {
                $item = New-Object System.Windows.Forms.ListViewItem($addResult.Code)
                [void]$item.SubItems.Add($addResult.Description)
                [void]$listView.Items.Add($item)
            }
        }
    })

    $btnEdit = New-Object System.Windows.Forms.Button
    $btnEdit.Text = "Edit..."
    $btnEdit.Width = 100
    $btnEdit.Location = New-Object System.Drawing.Point(375, 95)
    $btnEdit.Add_Click({
        if ($listView.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Select a code to edit.",
                "Edit Code",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $selectedItem = $listView.SelectedItems[0]
        $currentCode = $selectedItem.Text
        $currentDesc = $selectedItem.SubItems[1].Text

        $editResult = Show-AddSkipCodeDialog -Code $currentCode -Description $currentDesc
        if ($null -ne $editResult) {
            $selectedItem.Text = $editResult.Code
            $selectedItem.SubItems[1].Text = $editResult.Description
        }
    })

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove"
    $btnRemove.Width = 100
    $btnRemove.Location = New-Object System.Drawing.Point(375, 130)
    $btnRemove.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $selectedItem = $listView.SelectedItems[0]
            $listView.Items.Remove($selectedItem)
        }
    })

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Width = 80
    $btnOk.Location = New-Object System.Drawing.Point(310, 320)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Location = New-Object System.Drawing.Point(400, 320)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblDesc, $listView, $btnAdd, $btnEdit, $btnRemove, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        # Build new config from list
        $newConfig = @{
            version = 1
            skipCodes = @()
            skipCodeDescriptions = @{}
        }

        foreach ($item in $listView.Items) {
            $code = $item.Text
            $desc = $item.SubItems[1].Text
            $newConfig.skipCodes += $code
            if (-not [string]::IsNullOrWhiteSpace($desc)) {
                $newConfig.skipCodeDescriptions[$code] = $desc
            }
        }

        $saved = Save-ObxSkipConfig -Config $newConfig
        if ($saved) {
            [System.Windows.Forms.MessageBox]::Show(
                "OBX skip codes configuration saved.",
                "Configuration Saved",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        return $saved
    }

    return $false
}

function Show-AddSkipCodeDialog {
    <#
    .SYNOPSIS
    Show dialog to add or edit a skip code

    .PARAMETER Code
    Pre-fill code field (for editing)

    .PARAMETER Description
    Pre-fill description field (for editing)

    .OUTPUTS
    Hashtable with Code and Description, or $null if cancelled
    #>
    param(
        [string]$Code = "",
        [string]$Description = ""
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $isEdit = -not [string]::IsNullOrEmpty($Code)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($isEdit) { "Edit Skip Code" } else { "Add Skip Code" }
    $dialog.Width = 350
    $dialog.Height = 180
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $lblCode = New-Object System.Windows.Forms.Label
    $lblCode.Text = "Code:"
    $lblCode.Location = New-Object System.Drawing.Point(15, 20)
    $lblCode.Size = New-Object System.Drawing.Size(80, 20)

    $txtCode = New-Object System.Windows.Forms.TextBox
    $txtCode.Location = New-Object System.Drawing.Point(100, 17)
    $txtCode.Size = New-Object System.Drawing.Size(220, 20)
    $txtCode.Text = $Code
    $txtCode.MaxLength = 20

    $lblDescField = New-Object System.Windows.Forms.Label
    $lblDescField.Text = "Description:"
    $lblDescField.Location = New-Object System.Drawing.Point(15, 55)
    $lblDescField.Size = New-Object System.Drawing.Size(80, 20)

    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(100, 52)
    $txtDesc.Size = New-Object System.Drawing.Size(220, 20)
    $txtDesc.Text = $Description
    $txtDesc.MaxLength = 100

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Width = 80
    $btnOk.Location = New-Object System.Drawing.Point(155, 100)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Location = New-Object System.Drawing.Point(240, 100)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblCode, $txtCode, $lblDescField, $txtDesc, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $code = $txtCode.Text.Trim().ToUpper()
        if ([string]::IsNullOrWhiteSpace($code)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Code is required.",
                "Validation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return $null
        }

        return @{
            Code = $code
            Description = $txtDesc.Text.Trim()
        }
    }

    return $null
}
