function Get-BtnExportHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Return handler that shows the context menu
    return {
        param($sender, $e)
        
        # Create context menu for dropdown (create fresh each time to ensure proper scoping)
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Menu item 1: Export Selected as XML
        $menuItemXml = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemXml.Text = "Export Selected as XML"
        $menuItemXml.Add_Click((Get-BtnExportSelectedXmlHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemXml)
        
        # Menu item 2: Export All as CSV
        $menuItemAllCsv = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemAllCsv.Text = "Export All as CSV"
        $menuItemAllCsv.Add_Click((Get-BtnExportAllCsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemAllCsv)
        
        # Menu item 3: Export Selected as CSV
        $menuItemSelectedCsv = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSelectedCsv.Text = "Export Selected as CSV"
        $menuItemSelectedCsv.Add_Click((Get-BtnExportSelectedCsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemSelectedCsv)
        
        # Show context menu at button location (use sender which is the button)
        $button = $sender
        if ($null -eq $button) {
            $button = $Controls['btnExport']
        }
        
        if ($null -ne $button) {
            $contextMenu.Show($button, [System.Drawing.Point]::new(0, $button.Height))
        }
    }
}
