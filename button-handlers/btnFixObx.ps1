function Get-BtnFixObx3Handler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        # Validate HL7 file is loaded
        if ($null -eq $ScriptVars['Hl7Messages'] -or $ScriptVars['Hl7Messages'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Fix OBX3.1")
            return
        }
        
        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Fix OBX3.1")
            return
        }
        
        try {
            $Controls['lblStatus'].Text = "Fixing OBX segments..."
            $Controls['form'].Refresh()
            
            # Read the raw file content directly for maximum performance
            $rawContent = [System.IO.File]::ReadAllText($ScriptVars['CurrentFilePath'])
            
            # Process using high-performance raw content function
            $result = Fix-ObxInRawContent -RawContent $rawContent
            
            if ($result.FixedCount -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No truncated OBX segments found. All $($result.TotalObxCount) OBX segments are properly formatted.",
                    "Fix OBX3.1",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Hl7Messages'].Count
                return
            }
            
            # Generate output path with -obx suffix
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptVars['CurrentFilePath'])
            $extension = [System.IO.Path]::GetExtension($ScriptVars['CurrentFilePath'])
            $directory = [System.IO.Path]::GetDirectoryName($ScriptVars['CurrentFilePath'])
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-obx$extension")
            
            # Write the fixed content using .NET for speed
            [System.IO.File]::WriteAllText($outputPath, $result.ModifiedContent, [System.Text.Encoding]::ASCII)
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Hl7Messages'].Count
            
            $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                "Fixed $($result.FixedCount) of $($result.TotalObxCount) OBX segments.`n`nSaved to:`n$outputPath`n`nOpen containing folder?",
                "Fix OBX3.1 Complete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Process "explorer.exe" -ArgumentList "/select,`"$outputPath`""
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error fixing OBX segments: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error fixing OBX segments"
        }
    }
}

function Get-BtnFixObxHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Return handler that shows the context menu
    return {
        param($sender, $e)
        
        # Create context menu for dropdown (create fresh each time to ensure proper scoping)
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Menu item 1: Fix OBX3.1
        $menuItemFixObx3 = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemFixObx3.Text = "Fix OBX3.1"
        $menuItemFixObx3.Add_Click((Get-BtnFixObx3Handler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemFixObx3)
        
        # Menu item 2: Remove Empty OBX5
        $menuItemRemoveEmptyObx5 = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemRemoveEmptyObx5.Text = "Remove Empty OBX5"
        $menuItemRemoveEmptyObx5.Add_Click((Get-BtnRemoveEmptyObx5Handler -Controls $Controls -ScriptVars $ScriptVars))
        [void]$contextMenu.Items.Add($menuItemRemoveEmptyObx5)
        
        # Show context menu at button location (use sender which is the button)
        $button = $sender
        if ($null -eq $button) {
            $button = $Controls['btnFixObx']
        }
        
        if ($null -ne $button -and $null -ne $button.Owner) {
            # Convert button position to screen coordinates for ToolStripItem
            $screenPoint = $button.Owner.PointToScreen([System.Drawing.Point]::new($button.Bounds.Left, $button.Bounds.Bottom))
            $contextMenu.Show($screenPoint)
        }
    }
}
