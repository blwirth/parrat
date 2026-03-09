function Get-BtnExportAllHl7CsvHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Hl7Messages.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Export All")
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
                $Controls['lblStatus'].Text = "Exporting all {0} message(s) to CSV..." -f $script:Hl7Messages.Count
                $Controls['form'].Refresh()

                $result = Export-AllHl7Csv `
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

