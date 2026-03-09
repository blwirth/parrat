function Get-BtnNoahReportabilityHandler {
    param(
        [hashtable]$Controls
    )

    return {
        $fileType = $script:FileType
        $idx = [int]$script:CurrentIndex
        
        # Check for XML file
        if ($fileType -eq 'xml' -or $fileType -eq $null) {
            if ($script:Tumors.Count -eq 0 -or -not $script:XmlDoc -or -not $script:NsMgr) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No XML document loaded.",
                    "NOAH Reportability",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }

            if ($idx -lt 0 -or $idx -ge $script:Tumors.Count) {
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
                    -XmlDoc $script:XmlDoc `
                    -NsMgr $script:NsMgr `
                    -Config $config

                $recordLabel = "Tumor"
                $recordCount = $script:Tumors.Count
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

            try {
                $Controls['lblStatus'].Text = "NOAH reportability: running..."
                $Controls['form'].Refresh()

                $config = Get-NoahConfig
                $result = Invoke-NoahReportabilityFilterForMessage `
                    -MessageIndex $idx `
                    -Hl7Messages $script:Hl7Messages `
                    -Config $config

                $recordLabel = "Message"
                $recordCount = $script:Hl7Messages.Count
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

        if (-not $result.Success) {
            $msg = $result.Message
            if ($result.Errors) {
                $msg += "`n`nErrors:`n" + ($result.Errors -join "`n")
            }

            if ($result.WorkingFolder) {
                $msg += "`n`nWorking folder:`n$($result.WorkingFolder)"
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

        $class = $result.Classification
        $Controls['lblStatus'].Text = "NOAH reportability: {0}" -f $class

        # Look for the result JSON file in the reports folder
        $reportsFolder = Join-Path $result.WorkingFolder "reports"
        $resultFilePath = Get-NoahResultFile -ReportsFolder $reportsFolder

        if ($resultFilePath) {
            # Show the results viewer window
            Show-NoahResultsWindow `
                -ResultFilePath $resultFilePath `
                -WorkingFolder $result.WorkingFolder `
                -RecordLabel $recordLabel `
                -RecordIndex $idx `
                -RecordCount $recordCount
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
            $message += ("$recordLabel : {0} of {1}" -f ($idx + 1), $recordCount)
            $message += ("Result: {0}" -f $class.ToUpperInvariant())
            $message += ("Exit code: {0}" -f $result.ExitCode)
            $message += ""
            $message += "(No result JSON file found in reports folder)"
            $message += ""
            $message += "Working folder:"
            $message += $result.WorkingFolder

            $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                ($message -join "`r`n"),
                $title,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                $icon
            )

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                if ($result.WorkingFolder -and (Test-Path -LiteralPath $result.WorkingFolder)) {
                    Start-Process "explorer.exe" -ArgumentList "`"$($result.WorkingFolder)`""
                }
            }
        }
    }
}


