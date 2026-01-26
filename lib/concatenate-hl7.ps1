# concatenate-hl7.ps1
# NAACCR HL7 concatenation utilities

. "$PSScriptRoot\xml-helpers.ps1"

function Get-Hl7FileInfo {
    param(
        [string]$FilePath
    )
    
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding ASCII
        
        # Count messages (MSH| at start of line)
        $messageCount = ([regex]::Matches($content, "(?m)^MSH\|")).Count
        
        # Get file size
        $fileInfo = Get-Item $FilePath
        $fileSize = $fileInfo.Length
        
        return @{
            Success = $true
            MessageCount = $messageCount
            FileSize = $fileSize
            Content = $content
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-Hl7MessagePreview {
    param(
        [string]$Content,
        [int]$MaxMessages = 50
    )
    
    # Split by MSH| at start of line
    $messages = $Content -split "(?m)^MSH\|"
    $messages = $messages | Where-Object { $_ -match '\S' }
    
    $preview = @()
    $count = [Math]::Min($messages.Count, $MaxMessages)
    
    for ($i = 0; $i -lt $count; $i++) {
        $msg = $messages[$i]
        if (-not $msg.StartsWith("MSH|")) {
            $msg = "MSH|" + $msg
        }
        
        # Extract PID segment for patient info (if present)
        $pidMatch = [regex]::Match($msg, "(?m)^PID\|([^\r\n]+)")
        $pidLine = if ($pidMatch.Success) { $pidMatch.Groups[1].Value } else { "" }
        
        # Extract MSH segment for message type
        $mshMatch = [regex]::Match($msg, "(?m)^MSH\|([^\r\n]+)")
        $mshLine = if ($mshMatch.Success) { $mshMatch.Groups[1].Value } else { "" }
        
        # Parse PID fields (field 5 is patient name, field 3 is patient ID)
        $pidFields = if ($pidLine) { $pidLine -split '\|' } else { @() }
        $patientName = if ($pidFields.Count -gt 5) { $pidFields[5] } else { "" }
        $patientId = if ($pidFields.Count -gt 3) { $pidFields[3] } else { "" }
        
        # Parse MSH fields (field 9 is message type)
        $mshFields = if ($mshLine) { $mshLine -split '\|' } else { @() }
        $messageType = if ($mshFields.Count -gt 9) { $mshFields[9] } else { "" }
        
        $preview += [PSCustomObject]@{
            MessageIndex = $i + 1
            MessageType = $messageType
            PatientId = $patientId
            PatientName = $patientName
            Preview = if ($msg.Length -gt 200) { $msg.Substring(0, 200) + "..." } else { $msg }
        }
    }
    
    return $preview
}

function Show-Hl7ConcatenationPreview {
    param(
        [array]$Hl7Files,
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Use ArrayList for mutable file list that can be modified in event handlers
    $script:hl7FileInfos = New-Object System.Collections.ArrayList
    $errors = @()
    
    foreach ($file in $Hl7Files) {
        $info = Get-Hl7FileInfo -FilePath $file
        if (-not $info.Success) {
            $errors += "Error loading $file : $($info.Error)"
            continue
        }
        
        [void]$script:hl7FileInfos.Add(@{
            FilePath = $file
            Info = $info
        })
    }
    
    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Errors loading files:`n`n$($errors -join "`n")",
            "File Load Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    if ($script:hl7FileInfos.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No valid HL7 files found.",
            "No Files",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    # Create preview form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Concatenate HL7 Files - Preview"
    $previewForm.Width = 1600
    $previewForm.Height = 800
    $previewForm.StartPosition = "CenterScreen"
    
    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 40)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    # DataGridView for file list
    $gridFiles = New-Object System.Windows.Forms.DataGridView
    $gridFiles.Location = New-Object System.Drawing.Point(10, 60)
    $gridFiles.Size = New-Object System.Drawing.Size(1560, 580)
    $gridFiles.Anchor = 'Top,Left,Right,Bottom'
    $gridFiles.ReadOnly = $true
    $gridFiles.AllowUserToAddRows = $false
    $gridFiles.AllowUserToDeleteRows = $false
    $gridFiles.RowHeadersVisible = $false
    $gridFiles.AutoSizeColumnsMode = "AllCells"
    $gridFiles.SelectionMode = 'FullRowSelect'
    $gridFiles.MultiSelect = $false
    
    # Build file list DataTable
    $tableFiles = New-Object System.Data.DataTable
    [void]$tableFiles.Columns.Add("FileName", [string])
    [void]$tableFiles.Columns.Add("MessageCount", [int])
    [void]$tableFiles.Columns.Add("FileSizeMB", [string])
    [void]$tableFiles.Columns.Add("FilePath", [string])
    
    $gridFiles.DataSource = $tableFiles
    
    # Function to update the UI when file list changes
    $script:UpdateHl7PreviewUI = {
        # Calculate totals
        $totalMessages = 0
        $totalSize = 0
        foreach ($item in $script:hl7FileInfos) {
            $totalMessages += $item.Info.MessageCount
            $totalSize += $item.Info.FileSize
        }
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        
        # Update summary label
        $lblSummary.Text = "Files: $($script:hl7FileInfos.Count) | Total Messages: $totalMessages | Total Size: $totalSizeMB MB"
        
        # Update file list grid
        $tableFiles.Clear()
        foreach ($item in $script:hl7FileInfos) {
            $fileName = [System.IO.Path]::GetFileName($item.FilePath)
            $fileSizeMB = [math]::Round($item.Info.FileSize / 1MB, 2)
            $row = $tableFiles.NewRow()
            $row["FileName"] = $fileName
            $row["MessageCount"] = $item.Info.MessageCount
            $row["FileSizeMB"] = "$fileSizeMB MB"
            $row["FilePath"] = $item.FilePath
            [void]$tableFiles.Rows.Add($row)
        }
    }
    
    # Initial UI update
    & $script:UpdateHl7PreviewUI
    
    # File management buttons panel
    $pnlFileButtons = New-Object System.Windows.Forms.Panel
    $pnlFileButtons.Location = New-Object System.Drawing.Point(10, 650)
    $pnlFileButtons.Size = New-Object System.Drawing.Size(600, 35)
    $pnlFileButtons.Anchor = 'Bottom,Left'
    
    # Add More Files button
    $btnAddFiles = New-Object System.Windows.Forms.Button
    $btnAddFiles.Text = "Add More Files..."
    $btnAddFiles.Width = 120
    $btnAddFiles.Location = New-Object System.Drawing.Point(0, 0)
    
    # Remove Selected button
    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove Selected"
    $btnRemove.Width = 120
    $btnRemove.Location = New-Object System.Drawing.Point(130, 0)
    
    # Move Up button
    $btnMoveUp = New-Object System.Windows.Forms.Button
    $btnMoveUp.Text = "Move Up"
    $btnMoveUp.Width = 80
    $btnMoveUp.Location = New-Object System.Drawing.Point(260, 0)
    
    # Move Down button
    $btnMoveDown = New-Object System.Windows.Forms.Button
    $btnMoveDown.Text = "Move Down"
    $btnMoveDown.Width = 80
    $btnMoveDown.Location = New-Object System.Drawing.Point(350, 0)
    
    $pnlFileButtons.Controls.AddRange(@($btnAddFiles, $btnRemove, $btnMoveUp, $btnMoveDown))
    
    # Add More Files handler
    $btnAddFiles.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*"
        $ofd.Title = "Select additional HL7 files to add"
        $ofd.Multiselect = $true
        
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $addErrors = @()
            $addedCount = 0
            
            foreach ($file in $ofd.FileNames) {
                # Check if file already exists in list
                $exists = $script:hl7FileInfos | Where-Object { $_.FilePath -eq $file }
                if ($exists) {
                    $addErrors += "File already in list: $([System.IO.Path]::GetFileName($file))"
                    continue
                }
                
                $info = Get-Hl7FileInfo -FilePath $file
                if (-not $info.Success) {
                    $addErrors += "Error loading $file : $($info.Error)"
                    continue
                }
                
                [void]$script:hl7FileInfos.Add(@{
                    FilePath = $file
                    Info = $info
                })
                $addedCount++
            }
            
            if ($addErrors.Count -gt 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Some files could not be added:`n`n$($addErrors -join "`n")",
                    "Warning",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }
            
            if ($addedCount -gt 0) {
                & $script:UpdateHl7PreviewUI
            }
        }
    })
    
    # Remove Selected handler
    $btnRemove.Add_Click({
        if ($gridFiles.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please select a file to remove.",
                "No Selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        $selectedRow = $gridFiles.SelectedRows[0]
        $filePath = [string]$selectedRow.Cells["FilePath"].Value
        
        # Find and remove the item
        $itemToRemove = $null
        foreach ($item in $script:hl7FileInfos) {
            if ($item.FilePath -eq $filePath) {
                $itemToRemove = $item
                break
            }
        }
        
        if ($itemToRemove) {
            [void]$script:hl7FileInfos.Remove($itemToRemove)
            & $script:UpdateHl7PreviewUI
        }
    })
    
    # Move Up handler
    $btnMoveUp.Add_Click({
        if ($gridFiles.SelectedRows.Count -eq 0) { return }
        
        $selectedIndex = $gridFiles.SelectedRows[0].Index
        if ($selectedIndex -le 0) { return }
        
        # Swap items
        $temp = $script:hl7FileInfos[$selectedIndex]
        $script:hl7FileInfos[$selectedIndex] = $script:hl7FileInfos[$selectedIndex - 1]
        $script:hl7FileInfos[$selectedIndex - 1] = $temp
        
        & $script:UpdateHl7PreviewUI
        
        # Restore selection
        if ($gridFiles.Rows.Count -gt ($selectedIndex - 1)) {
            $gridFiles.ClearSelection()
            $gridFiles.Rows[$selectedIndex - 1].Selected = $true
        }
    })
    
    # Move Down handler
    $btnMoveDown.Add_Click({
        if ($gridFiles.SelectedRows.Count -eq 0) { return }
        
        $selectedIndex = $gridFiles.SelectedRows[0].Index
        if ($selectedIndex -ge ($script:hl7FileInfos.Count - 1)) { return }
        
        # Swap items
        $temp = $script:hl7FileInfos[$selectedIndex]
        $script:hl7FileInfos[$selectedIndex] = $script:hl7FileInfos[$selectedIndex + 1]
        $script:hl7FileInfos[$selectedIndex + 1] = $temp
        
        & $script:UpdateHl7PreviewUI
        
        # Restore selection
        if ($gridFiles.Rows.Count -gt ($selectedIndex + 1)) {
            $gridFiles.ClearSelection()
            $gridFiles.Rows[$selectedIndex + 1].Selected = $true
        }
    })
    
    # Action buttons
    $btnConcatenate = New-Object System.Windows.Forms.Button
    $btnConcatenate.Text = "Concatenate and Save"
    $btnConcatenate.Width = 180
    $btnConcatenate.Location = New-Object System.Drawing.Point(10, 710)
    $btnConcatenate.Anchor = 'Bottom,Left'
    
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(200, 710)
    $btnClose.Anchor = 'Bottom,Left'
    
    # Concatenate button handler
    $btnConcatenate.Add_Click({
        if ($script:hl7FileInfos.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No files to concatenate.",
                "No Files",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        # Get output directory
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select output directory for concatenated HL7 file"
        
        if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $outputDir = $folderDialog.SelectedPath
        
        # Get output filename
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Enter Output Filename"
        $inputForm.Width = 400
        $inputForm.Height = 150
        $inputForm.StartPosition = "CenterScreen"
        
        $lblPrompt = New-Object System.Windows.Forms.Label
        $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
        $lblPrompt.Size = New-Object System.Drawing.Size(370, 40)
        $lblPrompt.Text = "Enter the output filename (without .hl7 extension):"
        
        $txtFilename = New-Object System.Windows.Forms.TextBox
        $txtFilename.Location = New-Object System.Drawing.Point(10, 50)
        $txtFilename.Width = 370
        $txtFilename.Text = "concatenated"
        
        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.Location = New-Object System.Drawing.Point(200, 80)
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(280, 80)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        
        $inputForm.Controls.AddRange(@($lblPrompt, $txtFilename, $btnOk, $btnCancel))
        $inputForm.AcceptButton = $btnOk
        $inputForm.CancelButton = $btnCancel
        
        $result = $inputForm.ShowDialog()
        
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $filename = $txtFilename.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($filename)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Filename cannot be empty.",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }
        
        # Ensure .hl7 extension
        if (-not $filename.EndsWith(".hl7", [System.StringComparison]::OrdinalIgnoreCase)) {
            $filename += ".hl7"
        }
        
        $outputPath = [System.IO.Path]::Combine($outputDir, $filename)
        
        # Check if file exists
        if (Test-Path $outputPath) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                "File already exists:`n$outputPath`n`nOverwrite?",
                "File Exists",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }
        
        try {
            # Calculate total messages for success message
            $totalMessages = 0
            foreach ($item in $script:hl7FileInfos) {
                $totalMessages += $item.Info.MessageCount
            }

            # Concatenate HL7 files
            Write-ConcatenatedHl7 -FileInfos $script:hl7FileInfos -OutputPath $outputPath

            # Ask user if they want to open the newly created file
            $openResult = [System.Windows.Forms.MessageBox]::Show(
                "Concatenated HL7 file saved to:`n$outputPath`n`nTotal messages: $totalMessages`n`nOpen newly created file?",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            $previewForm.Close()

            if ($openResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Load the newly created file
                if ($Controls -ne $null -and $ScriptVars -ne $null) {
                    Import-Hl7File -FilePath $outputPath -Controls $Controls -ScriptVars $ScriptVars
                }
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error concatenating HL7 files: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })
    
    # Close button handler
    $btnClose.Add_Click({
        $previewForm.Close()
    })
    
    # Add controls to form
    $previewForm.Controls.AddRange(@($lblSummary, $gridFiles, $pnlFileButtons, $btnConcatenate, $btnClose))
    
    [void]$previewForm.ShowDialog()
    
    # Cleanup script-scoped variables
    $script:hl7FileInfos = $null
    $script:UpdateHl7PreviewUI = $null
}

function Write-ConcatenatedHl7 {
    param(
        [array]$FileInfos,
        [string]$OutputPath,
        [switch]$ShowProgress
    )
    
    # Use StreamWriter for efficient file writing - avoids O(n²) string concatenation
    $stream = $null
    try {
        $stream = New-Object System.IO.StreamWriter($OutputPath, $false, [System.Text.Encoding]::ASCII)
        $needsNewline = $false
        $totalFiles = $FileInfos.Count
        $currentFile = 0
        
        foreach ($item in $FileInfos) {
            $currentFile++
            
            if ($ShowProgress -and ($currentFile % 100 -eq 0 -or $currentFile -eq $totalFiles)) {
                Write-Progress -Activity "Concatenating HL7 files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
            }
            
            # Support both cached content and streaming from file path
            $content = if ($null -ne $item.Info -and $null -ne $item.Info.Content) {
                $item.Info.Content
            } elseif ($null -ne $item.FilePath -and (Test-Path $item.FilePath)) {
                Get-Content -Path $item.FilePath -Raw -Encoding ASCII
            } else {
                $null
            }
            
            if ([string]::IsNullOrEmpty($content)) { continue }
            
            # Trim trailing whitespace from content
            $trimmedContent = $content.TrimEnd("`r", "`n")
            if ([string]::IsNullOrEmpty($trimmedContent)) { continue }
            
            # Add newline separator between files to prevent MSH| from concatenating onto previous OBX
            if ($needsNewline) {
                $stream.Write("`r`n")
            }
            
            $stream.Write($trimmedContent)
            $needsNewline = $true
        }
        
        if ($ShowProgress) {
            Write-Progress -Activity "Concatenating HL7 files" -Completed
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Close()
            $stream.Dispose()
        }
    }
}

function Write-ConcatenatedHl7FromPaths {
    param(
        [string[]]$FilePaths,
        [string]$OutputPath
    )
    
    # Ultra-fast streaming mode - reads directly from files, no preview/caching
    # Use for very large batches (1000+ files)
    $stream = $null
    try {
        $stream = New-Object System.IO.StreamWriter($OutputPath, $false, [System.Text.Encoding]::ASCII)
        $needsNewline = $false
        $totalFiles = $FilePaths.Count
        $currentFile = 0
        
        foreach ($filePath in $FilePaths) {
            $currentFile++
            
            if ($currentFile % 100 -eq 0 -or $currentFile -eq $totalFiles) {
                Write-Progress -Activity "Concatenating HL7 files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
            }
            
            if (-not (Test-Path $filePath)) { continue }
            
            $content = Get-Content -Path $filePath -Raw -Encoding ASCII
            if ([string]::IsNullOrEmpty($content)) { continue }
            
            $trimmedContent = $content.TrimEnd("`r", "`n")
            if ([string]::IsNullOrEmpty($trimmedContent)) { continue }
            
            if ($needsNewline) {
                $stream.Write("`r`n")
            }
            
            $stream.Write($trimmedContent)
            $needsNewline = $true
        }
        
        Write-Progress -Activity "Concatenating HL7 files" -Completed
        
        return @{
            Success = $true
            FilesProcessed = $currentFile
            OutputPath = $OutputPath
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Close()
            $stream.Dispose()
        }
    }
}

function Start-ConcatenateHl7 {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    # Open file dialog for multiple file selection
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*"
    $ofd.Title = "Select HL7 files to concatenate (hold Ctrl or Shift to select multiple)"
    $ofd.Multiselect = $true

    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($ofd.FileNames.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No files selected.",
                "No Files",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        # For large batches, offer fast mode to skip preview
        if ($ofd.FileNames.Count -gt 500) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "You selected $($ofd.FileNames.Count) files.`n`nLoading all files for preview may be slow.`n`nWould you like to use Fast Mode?`n`n• Yes = Skip preview, concatenate directly (recommended for large batches)`n• No = Load preview (may take a while)`n• Cancel = Go back",
                "Large Batch Detected",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
                return
            }

            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-FastConcatenateHl7 -FilePaths $ofd.FileNames -Controls $Controls -ScriptVars $ScriptVars
                return
            }
        }

        Show-Hl7ConcatenationPreview -Hl7Files $ofd.FileNames -Controls $Controls -ScriptVars $ScriptVars
    }
}

function Start-FastConcatenateHl7 {
    param(
        [string[]]$FilePaths,
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    # Get output directory
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select output directory for concatenated HL7 file"
    
    if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    
    $outputDir = $folderDialog.SelectedPath
    
    # Get output filename
    $inputForm = New-Object System.Windows.Forms.Form
    $inputForm.Text = "Enter Output Filename"
    $inputForm.Width = 400
    $inputForm.Height = 150
    $inputForm.StartPosition = "CenterScreen"
    
    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
    $lblPrompt.Size = New-Object System.Drawing.Size(370, 40)
    $lblPrompt.Text = "Enter the output filename (without .hl7 extension):"
    
    $txtFilename = New-Object System.Windows.Forms.TextBox
    $txtFilename.Location = New-Object System.Drawing.Point(10, 50)
    $txtFilename.Width = 370
    $txtFilename.Text = "concatenated"
    
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(200, 80)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(280, 80)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    
    $inputForm.Controls.AddRange(@($lblPrompt, $txtFilename, $btnOk, $btnCancel))
    $inputForm.AcceptButton = $btnOk
    $inputForm.CancelButton = $btnCancel
    
    $dialogResult = $inputForm.ShowDialog()
    
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    
    $filename = $txtFilename.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($filename)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Filename cannot be empty.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    # Ensure .hl7 extension
    if (-not $filename.EndsWith(".hl7", [System.StringComparison]::OrdinalIgnoreCase)) {
        $filename += ".hl7"
    }
    
    $outputPath = [System.IO.Path]::Combine($outputDir, $filename)
    
    # Check if file exists
    if (Test-Path $outputPath) {
        $overwrite = [System.Windows.Forms.MessageBox]::Show(
            "File already exists:`n$outputPath`n`nOverwrite?",
            "File Exists",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }
    
    # Run concatenation with progress
    try {
        $result = Write-ConcatenatedHl7FromPaths -FilePaths $FilePaths -OutputPath $outputPath

        if ($result.Success) {
            $openResult = [System.Windows.Forms.MessageBox]::Show(
                "Concatenation complete!`n`nFiles processed: $($result.FilesProcessed)`nOutput: $outputPath`n`nOpen newly created file?",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($openResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Load the newly created file
                if ($Controls -ne $null -and $ScriptVars -ne $null) {
                    Import-Hl7File -FilePath $outputPath -Controls $Controls -ScriptVars $ScriptVars
                }
            }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Error during concatenation: $($result.Error)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error during concatenation: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}
