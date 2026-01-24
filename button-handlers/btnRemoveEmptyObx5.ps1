function Get-BtnRemoveEmptyObx5Handler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        # Validate HL7 file is loaded
        if ($null -eq $ScriptVars['Hl7Messages'] -or $ScriptVars['Hl7Messages'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Remove Empty OBX5")
            return
        }
        
        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Remove Empty OBX5")
            return
        }
        
        try {
            $Controls['lblStatus'].Text = "Removing empty OBX5 segments..."
            $Controls['form'].Refresh()

            Write-ParatLog -Level INFO -Message "Starting Remove Empty OBX5 for $($ScriptVars['Hl7Messages'].Count) messages" -Action "MODIFY_HL7"

            # Read the raw file content directly for maximum performance
            $rawContent = [System.IO.File]::ReadAllText($ScriptVars['CurrentFilePath'])

            # Process using high-performance raw content function
            $result = Remove-EmptyObx5FromRawContent -RawContent $rawContent

            if ($result.RemovedCount -eq 0) {
                Write-ParatLog -Level INFO -Message "Remove Empty OBX5: no empty segments found in $($result.TotalObxCount) OBX segments" -Action "MODIFY_HL7"
                [System.Windows.Forms.MessageBox]::Show(
                    "No empty OBX5 segments found. All $($result.TotalObxCount) OBX segments have values.",
                    "Remove Empty OBX5",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Hl7Messages'].Count
                return
            }

            # Generate output path with -no-empty-obx5 suffix
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptVars['CurrentFilePath'])
            $extension = [System.IO.Path]::GetExtension($ScriptVars['CurrentFilePath'])
            $directory = [System.IO.Path]::GetDirectoryName($ScriptVars['CurrentFilePath'])
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-no-empty-obx5$extension")

            # Write the modified content using .NET for speed
            [System.IO.File]::WriteAllText($outputPath, $result.ModifiedContent, [System.Text.Encoding]::ASCII)

            $outputFileName = [System.IO.Path]::GetFileName($outputPath)
            Write-ParatLog -Level INFO -Message "Remove Empty OBX5: removed $($result.RemovedCount) of $($result.TotalObxCount) segments, saved to $outputFileName" -Action "MODIFY_HL7"

            $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Hl7Messages'].Count

            $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                "Removed $($result.RemovedCount) of $($result.TotalObxCount) OBX segments with empty OBX5 values.`n`nSaved to:`n$outputPath`n`nOpen containing folder?",
                "Remove Empty OBX5 Complete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Process "explorer.exe" -ArgumentList "/select,`"$outputPath`""
            }
        }
        catch {
            Write-ParatError -Message "Remove Empty OBX5 failed" -Action "MODIFY_HL7" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error removing empty OBX5 segments: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error removing empty OBX5 segments"
        }
    }
}

