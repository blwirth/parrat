function Get-BtnExportHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Return handler that shows the context menu
    return {
        param($sender, $e)
        
        # Determine file type
        $fileType = $ScriptVars['FileType']
        $isXml = ($fileType -eq 'xml')
        $isHl7 = ($fileType -eq 'hl7')
        
        # Create context menu for dropdown (create fresh each time to ensure proper scoping)
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Menu item 1: Export Selected as XML
        $menuItemXml = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemXml.Text = "Export Selected as XML"
        $menuItemXml.Enabled = $isXml
        $menuItemXml.Add_Click((Get-BtnExportSelectedXmlHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemXml)

        # Menu item: Export Selected as HL7
        $menuItemHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemHl7.Text = "Export Selected as HL7"
        $menuItemHl7.Enabled = $isHl7
        $menuItemHl7.Add_Click((Get-BtnExportSelectedHl7Handler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemHl7)

        # Menu item: Test reportability using NOAH CLI (runs against a temp folder; original file is untouched)
        # NOAH only accepts HL7 files, so disable this option when XML is loaded
        $menuItemNoah = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemNoah.Text = "Test Reportability (NOAH)"
        $menuItemNoah.Enabled = $isHl7
        $menuItemNoah.Add_Click((Get-BtnNoahReportabilityHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemNoah)
        
        # Menu item 2: Export All as CSV (context-aware)
        $menuItemAllCsv = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemAllCsv.Text = "Export All as CSV"
        $menuItemAllCsv.Enabled = ($isXml -or $isHl7)
        if ($isXml) {
            $menuItemAllCsv.Add_Click((Get-BtnExportAllCsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        } elseif ($isHl7) {
            $menuItemAllCsv.Add_Click((Get-BtnExportAllHl7CsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        }
        [void]$contextMenu.Items.Add($menuItemAllCsv)
        
        # Menu item 3: Export Selected as CSV (context-aware)
        $menuItemSelectedCsv = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSelectedCsv.Text = "Export Selected as CSV"
        $menuItemSelectedCsv.Enabled = ($isXml -or $isHl7)
        if ($isXml) {
            $menuItemSelectedCsv.Add_Click((Get-BtnExportSelectedCsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        } elseif ($isHl7) {
            $menuItemSelectedCsv.Add_Click((Get-BtnExportSelectedHl7CsvHandler -Controls $Controls -ScriptVars $ScriptVars))
        }
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
