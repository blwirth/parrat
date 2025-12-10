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
        [array]$Hl7Files
    )
    
    # Load file info for all files
    $fileInfos = @()
    $errors = @()
    
    foreach ($file in $Hl7Files) {
        $info = Get-Hl7FileInfo -FilePath $file
        if (-not $info.Success) {
            $errors += "Error loading $file : $($info.Error)"
            continue
        }
        
        $fileInfos += @{
            FilePath = $file
            Info = $info
        }
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
    
    if ($fileInfos.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No valid HL7 files found.",
            "No Files",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    # Calculate totals
    $totalMessages = ($fileInfos | ForEach-Object { $_.Info.MessageCount } | Measure-Object -Sum).Sum
    $totalSize = ($fileInfos | ForEach-Object { $_.Info.FileSize } | Measure-Object -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    
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
    $lblSummary.Text = "Files: $($fileInfos.Count) | Total Messages: $totalMessages | Total Size: $totalSizeMB MB"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    # Split container for file list and message preview
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Location = New-Object System.Drawing.Point(10, 60)
    $splitContainer.Size = New-Object System.Drawing.Size(1560, 630)
    $splitContainer.Anchor = 'Top,Left,Right,Bottom'
    $splitContainer.Orientation = 'Vertical'
    $splitContainer.SplitterDistance = 300
    
    # DataGridView for file list (left)
    $gridFiles = New-Object System.Windows.Forms.DataGridView
    $gridFiles.Dock = 'Fill'
    $gridFiles.ReadOnly = $true
    $gridFiles.AllowUserToAddRows = $false
    $gridFiles.AllowUserToDeleteRows = $false
    $gridFiles.RowHeadersVisible = $false
    $gridFiles.AutoSizeColumnsMode = "Fill"
    $gridFiles.SelectionMode = 'FullRowSelect'
    $gridFiles.MultiSelect = $false
    
    # Build file list DataTable
    $tableFiles = New-Object System.Data.DataTable
    [void]$tableFiles.Columns.Add("FileName", [string])
    [void]$tableFiles.Columns.Add("MessageCount", [int])
    [void]$tableFiles.Columns.Add("FileSizeMB", [string])
    [void]$tableFiles.Columns.Add("FilePath", [string])
    
    foreach ($item in $fileInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $fileSizeMB = [math]::Round($item.Info.FileSize / 1MB, 2)
        $row = $tableFiles.NewRow()
        $row["FileName"] = $fileName
        $row["MessageCount"] = $item.Info.MessageCount
        $row["FileSizeMB"] = "$fileSizeMB MB"
        $row["FilePath"] = $item.FilePath
        [void]$tableFiles.Rows.Add($row)
    }
    
    $gridFiles.DataSource = $tableFiles
    
    # DataGridView for message preview (right)
    $gridMessages = New-Object System.Windows.Forms.DataGridView
    $gridMessages.Dock = 'Fill'
    $gridMessages.ReadOnly = $true
    $gridMessages.AllowUserToAddRows = $false
    $gridMessages.AllowUserToDeleteRows = $false
    $gridMessages.RowHeadersVisible = $false
    $gridMessages.AutoSizeColumnsMode = "Fill"
    $gridMessages.SelectionMode = 'FullRowSelect'
    $gridMessages.MultiSelect = $false
    
    # Build combined message preview DataTable
    $tableMessages = New-Object System.Data.DataTable
    [void]$tableMessages.Columns.Add("File", [string])
    [void]$tableMessages.Columns.Add("MessageIndex", [int])
    [void]$tableMessages.Columns.Add("MessageType", [string])
    [void]$tableMessages.Columns.Add("PatientId", [string])
    [void]$tableMessages.Columns.Add("PatientName", [string])
    
    # Combine all message previews
    foreach ($item in $fileInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $preview = Get-Hl7MessagePreview -Content $item.Info.Content
        
        foreach ($msg in $preview) {
            $row = $tableMessages.NewRow()
            $row["File"] = $fileName
            $row["MessageIndex"] = $msg.MessageIndex
            $row["MessageType"] = $msg.MessageType
            $row["PatientId"] = $msg.PatientId
            $row["PatientName"] = $msg.PatientName
            [void]$tableMessages.Rows.Add($row)
        }
    }
    
    $gridMessages.DataSource = $tableMessages
    
    # RichTextBox for message content preview (when a row is selected)
    $rtbPreview = New-Object System.Windows.Forms.RichTextBox
    $rtbPreview.Dock = 'Fill'
    $rtbPreview.ReadOnly = $true
    $rtbPreview.Font = New-Object System.Drawing.Font("Consolas", 9)
    $rtbPreview.WordWrap = $false
    
    # Inner split container for messages grid and preview
    $splitInner = New-Object System.Windows.Forms.SplitContainer
    $splitInner.Dock = 'Fill'
    $splitInner.Orientation = 'Horizontal'
    $splitInner.SplitterDistance = 300
    
    $splitInner.Panel1.Controls.Add($gridMessages)
    $splitInner.Panel2.Controls.Add($rtbPreview)
    
    # Add to split container
    $splitContainer.Panel1.Controls.Add($gridFiles)
    $splitContainer.Panel2.Controls.Add($splitInner)
    
    # Grid selection handler - show message content
    $gridMessages.Add_SelectionChanged({
        if ($gridMessages.SelectedRows.Count -eq 0) { return }
        
        $selectedRow = $gridMessages.SelectedRows[0]
        $fileName = [string]$selectedRow.Cells["File"].Value
        $msgIndex = [int]$selectedRow.Cells["MessageIndex"].Value - 1
        
        # Find the file and message
        $fileItem = $fileInfos | Where-Object { [System.IO.Path]::GetFileName($_.FilePath) -eq $fileName } | Select-Object -First 1
        if ($fileItem) {
            $messages = $fileItem.Info.Content -split "(?m)^MSH\|"
            $messages = $messages | Where-Object { $_ -match '\S' }
            
            if ($msgIndex -ge 0 -and $msgIndex -lt $messages.Count) {
                $msg = $messages[$msgIndex]
                if (-not $msg.StartsWith("MSH|")) {
                    $msg = "MSH|" + $msg
                }
                
                $rtbPreview.Clear()
                $rtbPreview.Text = $msg
            }
        }
    })
    
    # Buttons
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
            # Concatenate HL7 files
            Write-ConcatenatedHl7 -FileInfos $fileInfos -OutputPath $outputPath
            
            [System.Windows.Forms.MessageBox]::Show(
                "Concatenated HL7 file saved to:`n$outputPath`n`nTotal messages: $totalMessages",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            $previewForm.Close()
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
    $previewForm.Controls.AddRange(@($lblSummary, $splitContainer, $btnConcatenate, $btnClose))
    
    [void]$previewForm.ShowDialog()
}

function Write-ConcatenatedHl7 {
    param(
        [array]$FileInfos,
        [string]$OutputPath
    )
    
    $combinedContent = ""
    
    foreach ($item in $FileInfos) {
        $content = $item.Info.Content
        
        # Just append the content directly (no extra newlines)
        $combinedContent += $content
    }
    
    # Write with ASCII encoding and no trailing newline
    Set-Content -Path $OutputPath -Value $combinedContent -Encoding ASCII -NoNewline
}

function Start-ConcatenateHl7 {
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
        
        Show-Hl7ConcatenationPreview -Hl7Files $ofd.FileNames
    }
}

