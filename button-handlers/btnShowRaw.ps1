function Get-BtnShowRawHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        # Determine file type and record count
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

        # Use the first selected row for display
        $row = $Controls['gridNav'].SelectedRows[0]
        $val = $row.Cells["Index"].Value
        if ($null -eq $val) {
            [System.Windows.Forms.MessageBox]::Show("Unable to determine index for selected row.", "Show Raw")
            return
        }

        $idx = [int]$val - 1
        
        # Dispatch to appropriate raw viewer based on file type
        if ($fileType -eq 'hl7') {
            Show-RawHl7ForMessage -Index $idx
        }
        else {
            Show-RawXmlForTumor -Index $idx
        }
    }
}
