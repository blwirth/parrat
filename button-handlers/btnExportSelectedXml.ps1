function Get-BtnExportSelectedXmlHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Export Selected")
            return
        }

        if (-not $ScriptVars['XmlDoc'] -or -not $ScriptVars['NsMgr']) {
            [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Export Selected")
            return
        }

        # Commit any pending edits to the grid (important for checkboxes)
        $Controls['gridNav'].EndEdit()
        
        # Get checked tumor indices
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
                "Please select at least one tumor to export by checking the boxes in the first column.",
                "No Tumors Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        # Show preview first
        $previewResult = Show-XmlExportPreview `
            -TumorIndices $checkedIndices `
            -XmlDoc $ScriptVars['XmlDoc'] `
            -NsMgr $ScriptVars['NsMgr'] `
            -Title "Export Selected as XML - Preview"

        if ($previewResult -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        # Ask for output file
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
        $saveFileDialog.Title = "Save Exported XML File"
        
        # Suggest default filename based on current file
        if ($ScriptVars['CurrentFilePath']) {
            $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptVars['CurrentFilePath'])
            $saveFileDialog.FileName = "${inputFileName}_exported.xml"
            $saveFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($ScriptVars['CurrentFilePath'])
        }

        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $Controls['lblStatus'].Text = "Exporting {0} tumor(s)..." -f $checkedIndices.Count
                $Controls['form'].Refresh()

                $result = Export-SelectedXml `
                    -TumorIndices $checkedIndices `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -NsMgr $ScriptVars['NsMgr'] `
                    -OutputPath $saveFileDialog.FileName

                if ($result.Success) {
                    $outputFileName = [System.IO.Path]::GetFileName($saveFileDialog.FileName)
                    Write-ParatLog -Level INFO -Message "Exported $($result.ExportedCount) tumor(s) to $outputFileName" -Action "EXPORT"

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
                    Write-ParatLog -Level WARN -Message "XML export completed with errors" -Action "EXPORT"
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
                Write-ParatError -Message "XML export failed" -Action "EXPORT" -ErrorRecord $_
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

