function Get-BtnXmlHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Show XML")
            return
        }

        if ($Controls['gridNav'].SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select a row in the grid first.", "Show XML")
            return
        }

        # Use the first selected row for XML display
        $row = $Controls['gridNav'].SelectedRows[0]
        $val = $row.Cells["Index"].Value
        if ($null -eq $val) {
            [System.Windows.Forms.MessageBox]::Show("Unable to determine index for selected row.", "Show XML")
            return
        }

        $idx = [int]$val - 1
        Show-RawXmlForTumor -Index $idx -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr'] -XmlDoc $ScriptVars['XmlDoc']
    }
}
