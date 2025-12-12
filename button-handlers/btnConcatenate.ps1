function Get-BtnConcatenateHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Return handler that shows the context menu
    return {
        param($sender, $e)
        
        # Create context menu for dropdown (create fresh each time to ensure proper scoping)
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Menu item 1: Concatenate HL7
        $menuItemHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemHl7.Text = "Concatenate HL7"
        $menuItemHl7.Add_Click({
            Start-ConcatenateHl7
        })
        [void]$contextMenu.Items.Add($menuItemHl7)
        
        # Menu item 2: Concatenate XML
        $menuItemXml = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemXml.Text = "Concatenate XML"
        $menuItemXml.Add_Click({
            Start-ConcatenateXml
        })
        [void]$contextMenu.Items.Add($menuItemXml)
        
        # Show context menu at button location (use sender which is the button)
        $button = $sender
        if ($null -eq $button) {
            $button = $Controls['btnConcatenate']
        }
        
        if ($null -ne $button) {
            $contextMenu.Show($button, [System.Drawing.Point]::new(0, $button.Height))
        }
    }
}

