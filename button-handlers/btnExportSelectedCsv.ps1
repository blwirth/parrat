function Get-BtnExportSelectedCsvHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Export Selected")
            return
        }

        if (-not $script:XmlDoc -or -not $script:NsMgr) {
            [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Export Selected")
            return
        }

        # Commit any pending edits to the grid (important for checkboxes)
        $Controls['gridNav'].EndEdit()

        # Get checked tumor indices from the grid rows
        $checkedIndices = @()
        foreach ($row in $Controls['gridNav'].Rows) {
            # Use the cell's EditedFormattedValue which reflects the current visual state
            $cell = $row.Cells["Selected"]
            $isChecked = $cell.EditedFormattedValue -eq $true

            if ($isChecked) {
                $indexVal = $row.Cells["Index"].Value
                if ($null -ne $indexVal -and $indexVal -ne [System.DBNull]::Value) {
                    $checkedIndices += ([int]$indexVal - 1)
                }
            }
        }

        if ($checkedIndices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please select at least one tumor to export by checking the boxes in the first column.",
                "No Tumors Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
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

        # Show preview with integrated field selector
        $previewResult = Show-ExportPreview `
            -TumorIndices $checkedIndices `
            -XmlDoc $script:XmlDoc `
            -NsMgr $script:NsMgr `
            -FieldList $fieldList `
            -Title "Export Selected as CSV - Configure Fields & Preview"

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
            $saveFileDialog.FileName = "${inputFileName}_exported.csv"
            $saveFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:CurrentFilePath)
        }

        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $Controls['lblStatus'].Text = "Exporting {0} tumor(s) to CSV..." -f $checkedIndices.Count
                $Controls['form'].Refresh()

                $result = Export-SelectedCsv `
                    -TumorIndices $checkedIndices `
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
