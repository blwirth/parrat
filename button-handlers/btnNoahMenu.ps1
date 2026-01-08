function Invoke-PostSelectedHL7 {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    $fileType = $script:FileType
    $idx = [int]$ScriptVars['CurrentIndex']
    
    # Check for XML file
    if ($fileType -eq 'xml' -or $fileType -eq $null) {
        if ($ScriptVars['Tumors'].Count -eq 0 -or -not $ScriptVars['XmlDoc'] -or -not $ScriptVars['NsMgr']) {
            [System.Windows.Forms.MessageBox]::Show(
                "No XML document loaded.",
                "NOAH Reportability",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        if ($idx -lt 0 -or $idx -ge $ScriptVars['Tumors'].Count) {
            [System.Windows.Forms.MessageBox]::Show(
                "Select a tumor first (click a row in the left grid).",
                "NOAH Reportability",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        try {
            $Controls['lblStatus'].Text = "NOAH reportability: running..."
            $Controls['form'].Refresh()

            $config = Get-NoahConfig
            $result = Invoke-NoahReportabilityFilterForTumor `
                -TumorIndex $idx `
                -XmlDoc $ScriptVars['XmlDoc'] `
                -NsMgr $ScriptVars['NsMgr'] `
                -Config $config

            $recordLabel = "Tumor"
            $recordCount = $ScriptVars['Tumors'].Count
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
    }
    # Check for HL7 file
    elseif ($fileType -eq 'hl7') {
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

        try {
            $Controls['lblStatus'].Text = "NOAH reportability: running..."
            $Controls['form'].Refresh()

            $config = Get-NoahConfig
            $result = Invoke-NoahReportabilityFilterForMessage `
                -MessageIndex $idx `
                -Hl7Messages $ScriptVars['Hl7Messages'] `
                -Config $config

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
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "No file loaded.",
            "NOAH Reportability",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
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

    try {
        $Controls['lblStatus'].Text = "NOAH reportability (custom): running..."
        $Controls['form'].Refresh()

        $config = Get-NoahConfig
        $result = Invoke-NoahReportabilityFilterForCustomPayload `
            -CustomText $customText `
            -Config $config

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
        $message += "(No result JSON file found in reports folder)"
        $message += ""
        $message += "Working folder:"
        $message += $Result.WorkingFolder

        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            ($message -join "`r`n"),
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

function Get-BtnNoahMenuHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        # Create context menu
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

        # Menu item 1: POST Selected HL7
        $menuItemSelected = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSelected.Text = "POST Selected HL7"
        $menuItemSelected.Add_Click({
            Invoke-PostSelectedHL7 -Controls $Controls -ScriptVars $ScriptVars
        })

        # Menu item 2: POST Custom Payload
        $menuItemCustom = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemCustom.Text = "POST Custom Payload"
        $menuItemCustom.Add_Click({
            Invoke-PostCustomPayload -Controls $Controls -ScriptVars $ScriptVars
        })

        $contextMenu.Items.AddRange(@($menuItemSelected, $menuItemCustom))

        # Show the context menu at the button location
        $btn = $Controls['btnNoahMenu']
        $contextMenu.Show($btn, 0, $btn.Height)
    }
}
