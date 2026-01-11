function Invoke-PostSelectedHL7 {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    $fileType = $script:FileType
    # Try ScriptVars first, fall back to global (HL7 viewer updates global)
    $idx = $ScriptVars['CurrentIndex']
    if ($null -eq $idx -or $idx -lt 0) {
        $idx = $global:CurrentIndex
    }
    $idx = [int]$idx
    
    # Check for HL7 file (NOAH only accepts HL7 inputs)
    if ($fileType -ne 'hl7') {
        [System.Windows.Forms.MessageBox]::Show(
            "No HL7 file loaded. NOAH only accepts HL7 inputs.",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($ScriptVars['Hl7Messages'].Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No HL7 messages loaded.",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($idx -lt 0 -or $idx -ge $ScriptVars['Hl7Messages'].Count) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a message first (click a row in the left grid).",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    # Show model selection dialog (this starts the server)
    $config = Get-NoahConfig
    $selection = Show-NoahModelSelectionDialog -Config $config

    if ($null -eq $selection) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "NOAH reportability: running..."
        $Controls['form'].Refresh()

        # Server is already running from the dialog, pass the process handle
        $result = Invoke-NoahReportabilityFilterForMessage `
            -MessageIndex $idx `
            -Hl7Messages $ScriptVars['Hl7Messages'] `
            -Config $config `
            -ModelId $selection.ModelId `
            -OutputFormat $selection.OutputFormat `
            -ServerProcess $selection.ServerProcess

        $recordLabel = "Message"
        $recordCount = $ScriptVars['Hl7Messages'].Count
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error: $($_.Exception.Message)",
            "NOAH Reportability - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "NOAH reportability: error"
        return
    }

    Show-NoahResult -Result $result -Controls $Controls -RecordLabel $recordLabel -RecordIndex $idx -RecordCount $recordCount
}

function Invoke-PostCustomPayload {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    # Show dialog to get custom text
    $customText = Show-CustomPayloadDialog

    if ([string]::IsNullOrWhiteSpace($customText)) {
        return
    }

    # Show model selection dialog (this starts the server)
    $config = Get-NoahConfig
    $selection = Show-NoahModelSelectionDialog -Config $config

    if ($null -eq $selection) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "NOAH reportability (custom): running..."
        $Controls['form'].Refresh()

        # Server is already running from the dialog, pass the process handle
        $result = Invoke-NoahReportabilityFilterForCustomPayload `
            -CustomText $customText `
            -Config $config `
            -ModelId $selection.ModelId `
            -OutputFormat $selection.OutputFormat `
            -ServerProcess $selection.ServerProcess

        $recordLabel = "Custom Payload"
        $recordIndex = 0
        $recordCount = 1
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error: $($_.Exception.Message)",
            "NOAH Reportability - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "NOAH reportability: error"
        return
    }

    Show-NoahResult -Result $result -Controls $Controls -RecordLabel $recordLabel -RecordIndex $recordIndex -RecordCount $recordCount
}

function Show-NoahResult {
    param(
        [Parameter(Mandatory=$true)]$Result,
        [Parameter(Mandatory=$true)][hashtable]$Controls,
        [Parameter(Mandatory=$true)][string]$RecordLabel,
        [Parameter(Mandatory=$true)][int]$RecordIndex,
        [Parameter(Mandatory=$true)][int]$RecordCount
    )

    if (-not $Result.Success) {
        $msg = $Result.Message
        if ($Result.Errors) {
            $msg += "`n`nErrors:`n" + ($Result.Errors -join "`n")
        }

        if ($Result.WorkingFolder) {
            $msg += "`n`nWorking folder:`n$($Result.WorkingFolder)"
        }

        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "NOAH Reportability - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        $Controls['lblStatus'].Text = "NOAH reportability: error"
        return
    }

    $class = $Result.Classification
    $Controls['lblStatus'].Text = "NOAH reportability: {0}" -f $class

    # API-based results - show in message box
    $title = "NOAH Reportability"
    $icon  = [System.Windows.Forms.MessageBoxIcon]::Information

    if ($class -eq "reportable") { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
    elseif ($class -eq "nonreportable") { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
    elseif ($class -eq "mixed") { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
    else { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }

    $message = @()
    $message += ("$RecordLabel : {0} of {1}" -f ($RecordIndex + 1), $RecordCount)
    $message += ("Result: {0}" -f $class.ToUpperInvariant())
    
    if ($Result.ApiResponse) {
        $apiResp = $Result.ApiResponse
        if ($apiResp.impossibleCombination -eq "true") {
            $message += "Impossible Combination: Yes"
        }
        if ($apiResp.metastaticReport -eq $true) {
            $message += "Metastatic Report: Yes"
        }
    }

    [System.Windows.Forms.MessageBox]::Show(
        ($message -join "`r`n"),
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}

function Get-BtnNoahMenuHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        # Create context menu
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

        # Menu item 1: POST current HL7
        $menuItemSelected = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSelected.Text = "POST current HL7"
        $menuItemSelected.Add_Click({
            Invoke-PostSelectedHL7 -Controls $Controls -ScriptVars $ScriptVars
        })

        # Separator
        $separator = New-Object System.Windows.Forms.ToolStripSeparator

        # Menu item 2: POST custom payload
        $menuItemCustom = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemCustom.Text = "POST custom payload"
        $menuItemCustom.Add_Click({
            Invoke-PostCustomPayload -Controls $Controls -ScriptVars $ScriptVars
        })

        $contextMenu.Items.AddRange(@($menuItemSelected, $separator, $menuItemCustom))

        # Show the context menu at the button location
        $btn = $Controls['btnNoahMenu']
        $contextMenu.Show($btn, 0, $btn.Height)
    }
}
