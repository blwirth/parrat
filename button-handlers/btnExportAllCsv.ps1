function Get-BtnExportAllCsvHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Export All")
            return
        }

        if (-not $ScriptVars['XmlDoc'] -or -not $ScriptVars['NsMgr']) {
            [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Export All")
            return
        }

        # Define field list - map user-friendly names to XML field names
        $fieldList = @(
            "patientIdNumber",
            "nameLast",
            "nameFirst",
            "nameMiddle",
            "dateOfBirth",
            "reportingFacility",
            "dateOfDiagnosis",
            "pathReportNumber1",
            "primarySite",
            "histologicTypeIcdO3",
            "behaviorCodeIcdO3"
        )

        # Build list of all tumor indices
        $allIndices = @()
        for ($i = 0; $i -lt $ScriptVars['Tumors'].Count; $i++) {
            $allIndices += $i
        }

        # Show preview first
        $previewResult = Show-ExportPreview `
            -TumorIndices $allIndices `
            -XmlDoc $ScriptVars['XmlDoc'] `
            -NsMgr $ScriptVars['NsMgr'] `
            -FieldList $fieldList `
            -Title "Export All as CSV - Preview"

        if ($previewResult -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        # Ask for output file
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "CSV Files (*.csv)|*.csv|All files (*.*)|*.*"
        $saveFileDialog.Title = "Save Exported CSV File"
        
        # Suggest default filename based on current file
        if ($ScriptVars['CurrentFilePath']) {
            $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptVars['CurrentFilePath'])
            $saveFileDialog.FileName = "${inputFileName}_all_exported.csv"
            $saveFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($ScriptVars['CurrentFilePath'])
        }

        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $Controls['lblStatus'].Text = "Exporting all {0} tumor(s) to CSV..." -f $ScriptVars['Tumors'].Count
                $Controls['form'].Refresh()

                $result = Export-AllCsv `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -NsMgr $ScriptVars['NsMgr'] `
                    -OutputPath $saveFileDialog.FileName `
                    -FieldList $fieldList

                if ($result.Success) {
                    $message = "Successfully exported {0} tumor(s) to:`n{1}" -f $result.ExportedCount, $saveFileDialog.FileName
                    if ($result.Errors.Count -gt 0) {
                        $message += "`n`nErrors:`n" + ($result.Errors -join "`n")
                    }
                    
                    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                        $message,
                        "Export Complete",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )

                    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                        Start-Process "explorer.exe" -ArgumentList "/select,`"$($saveFileDialog.FileName)`""
                    }

                    $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
                }
                else {
                    $errorMessage = "Export completed with errors:`n" + ($result.Errors -join "`n")
                    [System.Windows.Forms.MessageBox]::Show(
                        $errorMessage,
                        "Export Errors",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    $Controls['lblStatus'].Text = "Export completed with errors"
                }
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Error during export: $($_.Exception.Message)",
                    "Export Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                $Controls['lblStatus'].Text = "Error during export"
            }
        }
    }
}

