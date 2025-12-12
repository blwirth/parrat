function Get-BtnDedupHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Return handler that shows the context menu
    return {
        param($sender, $e)
        
        # Create context menu for dropdown (create fresh each time to ensure proper scoping)
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Menu item 1: Dedup true matches
        $menuItemTrueMatches = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemTrueMatches.Text = "Dedup true matches"
        $menuItemTrueMatches.Add_Click((Get-BtnDedupTrueMatchesHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemTrueMatches)
        
        # Menu item 2: Dedup by pathReportNumber1
        $menuItemPathReport = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemPathReport.Text = "Dedup by pathReportNumber1"
        $menuItemPathReport.Add_Click((Get-BtnDedupPathReportHandler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemPathReport)
        
        # Show context menu at button location (use sender which is the button)
        $button = $sender
        if ($null -eq $button) {
            $button = $Controls['btnDedup']
        }
        
        if ($null -ne $button) {
            $contextMenu.Show($button, [System.Drawing.Point]::new(0, $button.Height))
        }
    }
}


