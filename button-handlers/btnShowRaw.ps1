function Get-BtnShowRawHandler {
    param(
        [hashtable]$Controls
    )
    
    return {
        try {
            $fileType = $script:FileType
            $recordCount = 0

            if ($fileType -eq 'hl7') {
                $recordCount = $script:Hl7Messages.Count
            }
            else {
                $recordCount = $script:Tumors.Count
            }

            if ($recordCount -eq 0) {
                $typeLabel = if ($fileType -eq 'hl7') { "messages" } else { "tumors" }
                [System.Windows.Forms.MessageBox]::Show("No $typeLabel loaded.", "Show Raw")
                return
            }

            if ($Controls['gridNav'].SelectedRows.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Please select a row in the grid first.", "Show Raw")
                return
            }

            $row = $Controls['gridNav'].SelectedRows[0]
            $val = $row.Cells["Index"].Value
            if ($null -eq $val) {
                [System.Windows.Forms.MessageBox]::Show("Unable to determine index for selected row.", "Show Raw")
                return
            }

            $idx = [int]$val - 1

            if ($fileType -eq 'hl7') {
                Show-RawHl7ForMessage -Index $idx
            }
            else {
                Show-RawXmlForTumor -Index $idx
            }
        }
        catch {
            Write-ParatError -Message "Show raw failed" -Action "SHOW_RAW" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error showing raw data: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}
