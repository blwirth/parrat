# concatenate-txt.ps1
# Text file concatenation utilities

function Get-TxtFileInfo {
    param(
        [string]$FilePath
    )
    
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        
        # Count lines
        $lineCount = ($content -split "`r`n|`n|`r").Count
        
        # Get file size
        $fileInfo = Get-Item $FilePath
        $fileSize = $fileInfo.Length
        
        return @{
            Success = $true
            LineCount = $lineCount
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

function Get-TxtFilePreview {
    param(
        [string]$Content,
        [int]$MaxLines = 50
    )
    
    # Split by lines
    $lines = $Content -split "`r`n|`n|`r"
    
    $preview = @()
    $count = [Math]::Min($lines.Count, $MaxLines)
    
    for ($i = 0; $i -lt $count; $i++) {
        $line = $lines[$i]
        $preview += [PSCustomObject]@{
            LineNumber = $i + 1
            LineContent = if ($line.Length -gt 200) { $line.Substring(0, 200) + "..." } else { $line }
        }
    }
    
    return $preview
}

function Show-TxtConcatenationPreview {
    param(
        [array]$TxtFiles
    )
    
    # Load file info for all files
    $fileInfos = @()
    $errors = @()
    
    foreach ($file in $TxtFiles) {
        $info = Get-TxtFileInfo -FilePath $file
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
            "No valid text files found.",
            "No Files",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    # Calculate totals
    $totalLines = ($fileInfos | ForEach-Object { $_.Info.LineCount } | Measure-Object -Sum).Sum
    $totalSize = ($fileInfos | ForEach-Object { $_.Info.FileSize } | Measure-Object -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    
    # Create preview form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Concatenate TXT Files - Preview"
    $previewForm.Width = 1600
    $previewForm.Height = 800
    $previewForm.StartPosition = "CenterScreen"
    
    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 40)
    $lblSummary.Text = "Files: $($fileInfos.Count) | Total Lines: $totalLines | Total Size: $totalSizeMB MB"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    # Split container for file list and content preview
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
    $gridFiles.AutoSizeColumnsMode = "AllCells"
    $gridFiles.SelectionMode = 'FullRowSelect'
    $gridFiles.MultiSelect = $false
    
    # Build file list DataTable
    $tableFiles = New-Object System.Data.DataTable
    [void]$tableFiles.Columns.Add("FileName", [string])
    [void]$tableFiles.Columns.Add("LineCount", [int])
    [void]$tableFiles.Columns.Add("FileSizeMB", [string])
    [void]$tableFiles.Columns.Add("FilePath", [string])
    
    foreach ($item in $fileInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $fileSizeMB = [math]::Round($item.Info.FileSize / 1MB, 2)
        $row = $tableFiles.NewRow()
        $row["FileName"] = $fileName
        $row["LineCount"] = $item.Info.LineCount
        $row["FileSizeMB"] = "$fileSizeMB MB"
        $row["FilePath"] = $item.FilePath
        [void]$tableFiles.Rows.Add($row)
    }
    
    $gridFiles.DataSource = $tableFiles
    
    # DataGridView for line preview (right top)
    $gridLines = New-Object System.Windows.Forms.DataGridView
    $gridLines.Dock = 'Fill'
    $gridLines.ReadOnly = $true
    $gridLines.AllowUserToAddRows = $false
    $gridLines.AllowUserToDeleteRows = $false
    $gridLines.RowHeadersVisible = $false
    $gridLines.AutoSizeColumnsMode = "AllCells"
    $gridLines.SelectionMode = 'FullRowSelect'
    $gridLines.MultiSelect = $false
    
    # Build combined line preview DataTable
    $tableLines = New-Object System.Data.DataTable
    [void]$tableLines.Columns.Add("File", [string])
    [void]$tableLines.Columns.Add("LineNumber", [int])
    [void]$tableLines.Columns.Add("LineContent", [string])
    
    # Combine all line previews
    foreach ($item in $fileInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $preview = Get-TxtFilePreview -Content $item.Info.Content
        
        foreach ($line in $preview) {
            $row = $tableLines.NewRow()
            $row["File"] = $fileName
            $row["LineNumber"] = $line.LineNumber
            $row["LineContent"] = $line.LineContent
            [void]$tableLines.Rows.Add($row)
        }
    }
    
    $gridLines.DataSource = $tableLines
    
    # RichTextBox for full content preview (right bottom)
    $rtbPreview = New-Object System.Windows.Forms.RichTextBox
    $rtbPreview.Dock = 'Fill'
    $rtbPreview.ReadOnly = $true
    $rtbPreview.Font = New-Object System.Drawing.Font("Consolas", 9)
    $rtbPreview.WordWrap = $false
    
    # Inner split container for lines grid and preview
    $splitInner = New-Object System.Windows.Forms.SplitContainer
    $splitInner.Dock = 'Fill'
    $splitInner.Orientation = 'Horizontal'
    $splitInner.SplitterDistance = 300
    
    $splitInner.Panel1.Controls.Add($gridLines)
    $splitInner.Panel2.Controls.Add($rtbPreview)
    
    # Add to split container
    $splitContainer.Panel1.Controls.Add($gridFiles)
    $splitContainer.Panel2.Controls.Add($splitInner)
    
    # Grid selection handler - show file content
    $gridFiles.Add_SelectionChanged({
        if ($gridFiles.SelectedRows.Count -eq 0) { return }
        
        $selectedRow = $gridFiles.SelectedRows[0]
        $filePath = [string]$selectedRow.Cells["FilePath"].Value
        
        # Find the file and show its content
        $fileItem = $fileInfos | Where-Object { $_.FilePath -eq $filePath } | Select-Object -First 1
        if ($fileItem) {
            $rtbPreview.Clear()
            $rtbPreview.Text = $fileItem.Info.Content
        }
    })
    
    # Grid selection handler - show line content in preview
    $gridLines.Add_SelectionChanged({
        if ($gridLines.SelectedRows.Count -eq 0) { return }
        
        $selectedRow = $gridLines.SelectedRows[0]
        $fileName = [string]$selectedRow.Cells["File"].Value
        
        # Find the file and show its content
        $fileItem = $fileInfos | Where-Object { [System.IO.Path]::GetFileName($_.FilePath) -eq $fileName } | Select-Object -First 1
        if ($fileItem) {
            $rtbPreview.Clear()
            $rtbPreview.Text = $fileItem.Info.Content
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
        $folderDialog.Description = "Select output directory for concatenated TXT file"
        
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
        $lblPrompt.Text = "Enter the output filename (without .txt extension):"
        
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
        
        # Ensure .txt extension
        if (-not $filename.EndsWith(".txt", [System.StringComparison]::OrdinalIgnoreCase)) {
            $filename += ".txt"
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
            # Concatenate TXT files
            Write-ConcatenatedTxt -FileInfos $fileInfos -OutputPath $outputPath
            
            [System.Windows.Forms.MessageBox]::Show(
                "Concatenated TXT file saved to:`n$outputPath`n`nTotal lines: $totalLines",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            $previewForm.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error concatenating TXT files: $($_.Exception.Message)",
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

function Write-ConcatenatedTxt {
    param(
        [array]$FileInfos,
        [string]$OutputPath
    )
    
    $combinedContent = ""
    
    foreach ($item in $FileInfos) {
        $content = $item.Info.Content
        
        # Append the content
        $combinedContent += $content
        
        # Add a blank line separator between files (ensure content ends with newline first)
        if (-not $content.EndsWith("`r`n") -and -not $content.EndsWith("`n") -and -not $content.EndsWith("`r")) {
            $combinedContent += "`r`n`r`n"
        } else {
            # Content already ends with newline, just add one more for separator
            $combinedContent += "`r`n"
        }
    }
    
    # Write with UTF8 encoding
    Set-Content -Path $OutputPath -Value $combinedContent -Encoding UTF8 -NoNewline
}

function Start-ConcatenateTxt {
    # Open file dialog for multiple file selection
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Text Files (*.txt)|*.txt|All files (*.*)|*.*"
    $ofd.Title = "Select TXT files to concatenate (hold Ctrl or Shift to select multiple)"
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
        
        Show-TxtConcatenationPreview -TxtFiles $ofd.FileNames
    }
}

