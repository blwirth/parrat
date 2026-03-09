function Invoke-PostSelectedHL7 {
    param(
        [hashtable]$Controls
    )

    $fileType = $script:FileType
    $idx = [int]$script:CurrentIndex
    
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

    if ($script:Hl7Messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No HL7 messages loaded.",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($idx -lt 0 -or $idx -ge $script:Hl7Messages.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a message first (click a row in the left grid).",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    # Show model selection dialog (loads from cache, no server needed)
    $config = Get-NoahConfig
    $selection = Show-NoahModelSelectionDialog -Config $config

    if ($null -eq $selection) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "NOAH reportability: running CLI..."
        $Controls['form'].Refresh()

        Write-ParatLog -Level INFO -Message "Starting NOAH filter for message $($idx + 1)" -Action "NOAH_API"

        # Run CLI-based filter (no server needed)
        $result = Invoke-NoahReportabilityFilterForMessage `
            -MessageIndex $idx `
            -Hl7Messages $script:Hl7Messages `
            -Config $config `
            -ModelId $selection.ModelId `
            -OutputFormat $selection.OutputFormat

        $recordLabel = "Message"
        $recordCount = $script:Hl7Messages.Count

        if ($result.Success) {
            Write-ParatLog -Level INFO -Message "NOAH filter completed: $($result.Classification)" -Action "NOAH_API"
        } else {
            Write-ParatLog -Level WARN -Message "NOAH filter returned error" -Action "NOAH_API"
        }
    }
    catch {
        Write-ParatError -Message "NOAH filter failed" -Action "NOAH_API" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error: $($_.Exception.Message)",
            "NOAH Reportability - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "NOAH reportability: error"
        return
    }

    Show-NoahCliResult -Result $result -Controls $Controls -RecordLabel $recordLabel -RecordIndex $idx -RecordCount $recordCount
}

function Invoke-PostCustomPayload {
    param(
        [hashtable]$Controls
    )

    # Show dialog to get custom text
    $customText = Show-CustomPayloadDialog

    if ([string]::IsNullOrWhiteSpace($customText)) {
        return
    }

    # Show model selection dialog (loads from cache, no server needed)
    $config = Get-NoahConfig
    $selection = Show-NoahModelSelectionDialog -Config $config

    if ($null -eq $selection) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "NOAH reportability (custom): running CLI..."
        $Controls['form'].Refresh()

        Write-ParatLog -Level INFO -Message "Starting NOAH filter for custom payload" -Action "NOAH_API"

        # Run CLI-based filter (no server needed)
        $result = Invoke-NoahReportabilityFilterForCustomPayload `
            -CustomText $customText `
            -Config $config `
            -ModelId $selection.ModelId `
            -OutputFormat $selection.OutputFormat

        $recordLabel = "Custom Payload"
        $recordIndex = 0
        $recordCount = 1

        if ($result.Success) {
            Write-ParatLog -Level INFO -Message "NOAH filter (custom) completed: $($result.Classification)" -Action "NOAH_API"
        } else {
            Write-ParatLog -Level WARN -Message "NOAH filter (custom) returned error" -Action "NOAH_API"
        }
    }
    catch {
        Write-ParatError -Message "NOAH filter (custom) failed" -Action "NOAH_API" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error: $($_.Exception.Message)",
            "NOAH Reportability - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "NOAH reportability: error"
        return
    }

    Show-NoahCliResult -Result $result -Controls $Controls -RecordLabel $recordLabel -RecordIndex $recordIndex -RecordCount $recordCount
}

function Show-NoahCliResult {
    <#
    .SYNOPSIS
    Show NOAH CLI results - looks for result JSON and shows results viewer
    #>
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

    # Look for the result JSON file in the reports folder
    $reportsFolder = Join-Path $Result.WorkingFolder "reports"
    $resultFilePath = Get-NoahResultFile -ReportsFolder $reportsFolder

    if ($resultFilePath) {
        # Show the results viewer window
        Show-NoahResultsWindow `
            -ResultFilePath $resultFilePath `
            -WorkingFolder $Result.WorkingFolder `
            -RecordLabel $RecordLabel `
            -RecordIndex $RecordIndex `
            -RecordCount $RecordCount
    }
    else {
        # Fallback to simple message box if no result file found
        $title = "NOAH Reportability"
        $icon  = [System.Windows.Forms.MessageBoxIcon]::Information

        if ($class -eq "reportable") { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
        elseif ($class -eq "nonreportable") { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
        elseif ($class -eq "mixed") { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
        else { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }

        $message = @()
        $message += ("$RecordLabel : {0} of {1}" -f ($RecordIndex + 1), $RecordCount)
        $message += ("Result: {0}" -f $class.ToUpperInvariant())
        $message += ("Exit code: {0}" -f $Result.ExitCode)
        $message += ""
        $message += "Working folder:"
        $message += $Result.WorkingFolder

        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            ($message -join "`r`n") + "`r`n`r`nOpen working folder?",
            $title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            $icon
        )

        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            if ($Result.WorkingFolder -and (Test-Path -LiteralPath $Result.WorkingFolder)) {
                Start-Process "explorer.exe" -ArgumentList "`"$($Result.WorkingFolder)`""
            }
        }
    }
}

function Invoke-NoahSettings {
    <#
    .SYNOPSIS
    Open NOAH Settings dialog
    #>
    param(
        [hashtable]$Controls
    )

    $config = Get-NoahConfig
    $saved = Show-NoahSettingsDialog -Config $config

    if ($saved) {
        Write-ParatLog -Level INFO -Message "NOAH configuration updated" -Action "CONFIG_CHANGE"
        $Controls['lblStatus'].Text = "NOAH settings saved"
    }
}

function Get-BtnNoahMenuHandler {
    param(
        [hashtable]$Controls
    )

    return {
        # Create context menu
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

        # Menu item 1: Test current HL7
        $menuItemSelected = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSelected.Text = "Test current HL7"
        $menuItemSelected.Add_Click({
            Invoke-PostSelectedHL7 -Controls $Controls
        })

        # Menu item 2: Test custom payload
        $menuItemCustom = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemCustom.Text = "Test custom payload"
        $menuItemCustom.Add_Click({
            Invoke-PostCustomPayload -Controls $Controls
        })

        # Separator
        $separator = New-Object System.Windows.Forms.ToolStripSeparator

        # Menu item 3: Settings
        $menuItemSettings = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSettings.Text = "Settings..."
        $menuItemSettings.Add_Click({
            Invoke-NoahSettings -Controls $Controls
        })

        $contextMenu.Items.AddRange(@($menuItemSelected, $menuItemCustom, $separator, $menuItemSettings))

        # Show the context menu at the button location
        $btn = $Controls['btnNoahMenu']
        $contextMenu.Show($btn, 0, $btn.Height)
    }
}
