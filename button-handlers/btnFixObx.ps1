function Get-BtnFixObxHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        # Validate HL7 file is loaded
        if ($null -eq $ScriptVars['Hl7Messages'] -or $ScriptVars['Hl7Messages'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Fix OBX")
            return
        }
        
        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Fix OBX")
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
                    "Fix OBX",
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
                "Fix OBX Complete",
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
