function Get-BtnExportSelectedHl7CsvHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Hl7Messages.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Export Selected")
            return
        }

        # Commit any pending edits to the grid (important for checkboxes)
        $Controls['gridNav'].EndEdit()

        # Get checked message indices
        $checkedIndices = @()
        foreach ($row in $Controls['gridNav'].Rows) {
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
                "Please select at least one message to export by checking the boxes in the first column.",
                "No Messages Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
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
                $Controls['lblStatus'].Text = "Exporting {0} message(s) to CSV..." -f $checkedIndices.Count
                $Controls['form'].Refresh()

                $result = Export-SelectedHl7Csv `
                    -MessageIndices $checkedIndices `
                    -Hl7Messages $script:Hl7Messages `
                    -OutputPath $saveFileDialog.FileName

                if ($result.Success) {
                    $message = "Successfully exported {0} message(s) to:`n{1}" -f $result.ExportedCount, $saveFileDialog.FileName
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

                    $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Hl7Messages.Count
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

