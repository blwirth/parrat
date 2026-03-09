function Get-BtnExportAllCsvHandler {
    param(
        [hashtable]$Controls
    )
    
    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Export All")
            return
        }

        if (-not $script:XmlDoc -or -not $script:NsMgr) {
            [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Export All")
            return
        }

        # Define default field list
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
        for ($i = 0; $i -lt $script:Tumors.Count; $i++) {
            $allIndices += $i
        }

        # Show preview with integrated field selector
        $previewResult = Show-ExportPreview `
            -TumorIndices $allIndices `
            -XmlDoc $script:XmlDoc `
            -NsMgr $script:NsMgr `
            -FieldList $fieldList `
            -Title "Export All as CSV - Configure Fields & Preview"

        # Check if user confirmed export
        if ($previewResult.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        # Get the configured field list and custom fields from preview
        $configuredFieldList = $previewResult.FieldList
        $customFields = $previewResult.CustomFields

        if ($configuredFieldList.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No fields selected for export.",
                "Export Cancelled",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # Ask for output file
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "CSV Files (*.csv)|*.csv|All files (*.*)|*.*"
        $saveFileDialog.Title = "Save Exported CSV File"
        
        # Suggest default filename based on current file
        if ($script:CurrentFilePath) {
            $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($script:CurrentFilePath)
            $saveFileDialog.FileName = "${inputFileName}_all_exported.csv"
            $saveFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:CurrentFilePath)
        }

        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $Controls['lblStatus'].Text = "Exporting all {0} tumor(s) to CSV..." -f $script:Tumors.Count
                $Controls['form'].Refresh()

                $result = Export-AllCsv `
                    -XmlDoc $script:XmlDoc `
                    -NsMgr $script:NsMgr `
                    -OutputPath $saveFileDialog.FileName `
                    -FieldList $configuredFieldList `
                    -CustomFields $customFields

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

                    $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
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
