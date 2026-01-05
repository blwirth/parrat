function Get-BtnNoahReportabilityHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        if ($ScriptVars['Tumors'].Count -eq 0 -or -not $ScriptVars['XmlDoc'] -or -not $ScriptVars['NsMgr']) {
            [System.Windows.Forms.MessageBox]::Show(
                "No XML document loaded.",
                "NOAH Reportability",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $idx = [int]$ScriptVars['CurrentIndex']
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
                    -RecordLabel "Tumor" `
                    -RecordIndex $idx `
                    -RecordCount $ScriptVars['Tumors'].Count
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
                $message += ("Tumor: {0} of {1}" -f ($idx + 1), $ScriptVars['Tumors'].Count)
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
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Unexpected error: $($_.Exception.Message)",
                "NOAH Reportability - Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            $Controls['lblStatus'].Text = "NOAH reportability: error"
        }
    }
}


