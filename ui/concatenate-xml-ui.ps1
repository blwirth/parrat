# concatenate-xml-ui.ps1
# UI dialogs for XML concatenation

function Show-DuplicatePatientIdWarning {
    param(
        [hashtable]$Duplicates
    )

    $warningForm = New-Object System.Windows.Forms.Form
    $warningForm.Text = "Duplicate Patient IDs Detected"
    $warningForm.Width = 500
    $warningForm.Height = 350
    $warningForm.StartPosition = "CenterScreen"
    $warningForm.FormBorderStyle = 'FixedDialog'
    $warningForm.MaximizeBox = $false
    $warningForm.MinimizeBox = $false

    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Location = New-Object System.Drawing.Point(10, 10)
    $lblWarning.Size = New-Object System.Drawing.Size(470, 40)
    $lblWarning.Text = "Warning: The following patient IDs appear in multiple files. This may cause issues in downstream systems."
    $lblWarning.ForeColor = [System.Drawing.Color]::DarkRed

    # List duplicates in a textbox
    $txtDuplicates = New-Object System.Windows.Forms.TextBox
    $txtDuplicates.Location = New-Object System.Drawing.Point(10, 55)
    $txtDuplicates.Size = New-Object System.Drawing.Size(465, 150)
    $txtDuplicates.Multiline = $true
    $txtDuplicates.ScrollBars = "Vertical"
    $txtDuplicates.ReadOnly = $true
    $txtDuplicates.Font = New-Object System.Drawing.Font("Consolas", 9)

    $duplicateText = ""
    foreach ($key in $Duplicates.Keys | Sort-Object) {
        $duplicateText += "Patient ID '$key' appears $($Duplicates[$key]) times`r`n"
    }
    $txtDuplicates.Text = $duplicateText.TrimEnd()

    # Result variable
    $script:duplicateDialogResult = "Cancel"

    # Reassign button (recommended)
    $btnReassign = New-Object System.Windows.Forms.Button
    $btnReassign.Text = "Reassign All Patient IDs (Start at 1)"
    $btnReassign.Width = 220
    $btnReassign.Height = 30
    $btnReassign.Location = New-Object System.Drawing.Point(10, 220)
    $btnReassign.Add_Click({
        $script:duplicateDialogResult = "Reassign"
        $warningForm.Close()
    })

    # Keep existing button (red/warning)
    $btnKeep = New-Object System.Windows.Forms.Button
    $btnKeep.Text = "Concatenate Anyway (Keep IDs)"
    $btnKeep.Width = 220
    $btnKeep.Height = 30
    $btnKeep.Location = New-Object System.Drawing.Point(10, 260)
    $btnKeep.ForeColor = [System.Drawing.Color]::DarkRed
    $btnKeep.Add_Click({
        $script:duplicateDialogResult = "Keep"
        $warningForm.Close()
    })

    # Cancel button
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Height = 30
    $btnCancel.Location = New-Object System.Drawing.Point(375, 260)
    $btnCancel.Add_Click({
        $script:duplicateDialogResult = "Cancel"
        $warningForm.Close()
    })

    $warningForm.Controls.AddRange(@($lblWarning, $txtDuplicates, $btnReassign, $btnKeep, $btnCancel))
    $warningForm.CancelButton = $btnCancel

    [void]$warningForm.ShowDialog()

    return $script:duplicateDialogResult
}

function Show-ConcatenationPreview {
    param(
        [array]$XmlFiles,
        [hashtable]$Controls
    )

    # Validate headers
    $validation = Test-XmlHeaders -XmlFiles $XmlFiles
    if (-not $validation.Success) {
        [System.Windows.Forms.MessageBox]::Show(
            "Cannot concatenate XMLs:`n`n$($validation.Error)",
            "Validation Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    # Use ArrayList for mutable file list that can be modified in event handlers
    $script:xmlFileInfos = New-Object System.Collections.ArrayList
    foreach ($item in $validation.HeaderInfos) {
        [void]$script:xmlFileInfos.Add($item)
    }

    # Store reference info for header validation when adding new files
    $script:xmlRefInfo = $validation.ReferenceInfo

    # Store Controls for access in event handlers
    $script:concatControls = $Controls

    # Store output path for loading after form closes
    $script:concatOutputPath = $null
    $script:concatShouldOpen = $false

    # Create preview form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Concatenate XML Files - Preview"
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
    [void]$tableFiles.Columns.Add("TumorCount", [int])
    [void]$tableFiles.Columns.Add("FilePath", [string])

    $gridFiles.DataSource = $tableFiles

    # Function to update the UI when file list changes
    $script:UpdateXmlPreviewUI = {
        # Calculate totals
        $totalTumors = 0
        foreach ($item in $script:xmlFileInfos) {
            $totalTumors += $item.Info.TumorCount
        }

        # Update summary label
        $lblSummary.Text = "Files: $($script:xmlFileInfos.Count) | Total Tumors: $totalTumors | XML Version: $($script:xmlRefInfo.XmlVersion) | Record Type: $($script:xmlRefInfo.RecordType)"

        # Update file list grid
        $tableFiles.Clear()
        foreach ($item in $script:xmlFileInfos) {
            $fileName = [System.IO.Path]::GetFileName($item.FilePath)
            $row = $tableFiles.NewRow()
            $row["FileName"] = $fileName
            $row["TumorCount"] = $item.Info.TumorCount
            $row["FilePath"] = $item.FilePath
            [void]$tableFiles.Rows.Add($row)
        }
    }

    # Initial UI update
    & $script:UpdateXmlPreviewUI

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
        $ofd.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
        $ofd.Title = "Select additional XML files to add"
        $ofd.Multiselect = $true

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $addErrors = @()
            $addedCount = 0

            foreach ($file in $ofd.FileNames) {
                # Check if file already exists in list
                $exists = $script:xmlFileInfos | Where-Object { $_.FilePath -eq $file }
                if ($exists) {
                    $addErrors += "File already in list: $([System.IO.Path]::GetFileName($file))"
                    continue
                }

                $info = Get-XmlHeaderInfo -FilePath $file
                if (-not $info.Success) {
                    $addErrors += "Error loading $file : $($info.Error)"
                    continue
                }

                # Validate headers match reference
                $headerValidation = Test-XmlHeaderAgainstReference -NewInfo $info -ReferenceInfo $script:xmlRefInfo
                if (-not $headerValidation.Success) {
                    $addErrors += "File '$([System.IO.Path]::GetFileName($file))' headers don't match:`n$($headerValidation.Error)"
                    continue
                }

                [void]$script:xmlFileInfos.Add(@{
                    FilePath = $file
                    Info = $info
                })
                $addedCount++
            }

            if ($addErrors.Count -gt 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Some files could not be added:`n`n$($addErrors -join "`n`n")",
                    "Warning",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }

            if ($addedCount -gt 0) {
                & $script:UpdateXmlPreviewUI
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
        foreach ($item in $script:xmlFileInfos) {
            if ($item.FilePath -eq $filePath) {
                $itemToRemove = $item
                break
            }
        }

        if ($itemToRemove) {
            [void]$script:xmlFileInfos.Remove($itemToRemove)
            & $script:UpdateXmlPreviewUI
        }
    })

    # Move Up handler
    $btnMoveUp.Add_Click({
        if ($gridFiles.SelectedRows.Count -eq 0) { return }

        $selectedIndex = $gridFiles.SelectedRows[0].Index
        if ($selectedIndex -le 0) { return }

        # Swap items
        $temp = $script:xmlFileInfos[$selectedIndex]
        $script:xmlFileInfos[$selectedIndex] = $script:xmlFileInfos[$selectedIndex - 1]
        $script:xmlFileInfos[$selectedIndex - 1] = $temp

        & $script:UpdateXmlPreviewUI

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
        if ($selectedIndex -ge ($script:xmlFileInfos.Count - 1)) { return }

        # Swap items
        $temp = $script:xmlFileInfos[$selectedIndex]
        $script:xmlFileInfos[$selectedIndex] = $script:xmlFileInfos[$selectedIndex + 1]
        $script:xmlFileInfos[$selectedIndex + 1] = $temp

        & $script:UpdateXmlPreviewUI

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
        if ($script:xmlFileInfos.Count -eq 0) {
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
        $folderDialog.Description = "Select output directory for concatenated XML"

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
        $lblPrompt.Text = "Enter the output filename (without .xml extension):"

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

        # Ensure .xml extension
        if (-not $filename.EndsWith(".xml", [System.StringComparison]::OrdinalIgnoreCase)) {
            $filename += ".xml"
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
            # Calculate total tumors for success message
            $totalTumors = 0
            foreach ($item in $script:xmlFileInfos) {
                $totalTumors += $item.Info.TumorCount
            }

            # Check for duplicate patient IDs
            $duplicates = Get-DuplicatePatientIds -HeaderInfos $script:xmlFileInfos
            $reassignIds = $false

            if ($duplicates.Count -gt 0) {
                $dialogResult = Show-DuplicatePatientIdWarning -Duplicates $duplicates

                if ($dialogResult -eq "Cancel") {
                    return
                }
                elseif ($dialogResult -eq "Reassign") {
                    $reassignIds = $true
                }
                # else "Keep" - continue with existing IDs
            }

            # Concatenate XMLs
            Write-ConcatenatedXml -HeaderInfos $script:xmlFileInfos -ReferenceInfo $script:xmlRefInfo -OutputPath $outputPath -ReassignPatientIds:$reassignIds

            # Ask user if they want to open the newly created file
            $openResult = [System.Windows.Forms.MessageBox]::Show(
                "Concatenated XML saved to:`n$outputPath`n`nTotal tumors: $totalTumors`n`nOpen newly created file?",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            # Store for loading after form closes
            if ($openResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                $script:concatOutputPath = $outputPath
                $script:concatShouldOpen = $true
            }

            $previewForm.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error concatenating XMLs: $($_.Exception.Message)",
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

    # Load file after form closes if user requested
    if ($script:concatShouldOpen -and $script:concatOutputPath) {
        if ($script:concatControls -ne $null) {
            Import-XmlFile -FilePath $script:concatOutputPath -Controls $script:concatControls
        }
    }

    # Cleanup script-scoped variables
    $script:xmlFileInfos = $null
    $script:xmlRefInfo = $null
    $script:UpdateXmlPreviewUI = $null
    $script:concatControls = $null
    $script:concatOutputPath = $null
    $script:concatShouldOpen = $false
}

function Start-ConcatenateXml {
    param(
        [hashtable]$Controls
    )

    # Open file dialog for multiple file selection
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
    $ofd.Title = "Select XML files to concatenate (hold Ctrl or Shift to select multiple)"
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
        if ($ofd.FileNames.Count -gt 200) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "You selected $($ofd.FileNames.Count) files.`n`nLoading and validating all XML files for preview may be slow.`n`nWould you like to use Fast Mode?`n`n• Yes = Skip preview, concatenate directly (recommended for large batches)`n• No = Load preview with full validation (may take a while)`n• Cancel = Go back",
                "Large Batch Detected",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
                return
            }

            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-FastConcatenateXml -FilePaths $ofd.FileNames -Controls $Controls
                return
            }
        }

        Show-ConcatenationPreview -XmlFiles $ofd.FileNames -Controls $Controls
    }
}

function Start-FastConcatenateXml {
    param(
        [string[]]$FilePaths,
        [hashtable]$Controls
    )

    # Get output directory
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select output directory for concatenated XML"

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
    $lblPrompt.Text = "Enter the output filename (without .xml extension):"

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

    # Ensure .xml extension
    if (-not $filename.EndsWith(".xml", [System.StringComparison]::OrdinalIgnoreCase)) {
        $filename += ".xml"
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
        $result = Write-ConcatenatedXmlFromPaths -FilePaths $FilePaths -OutputPath $outputPath

        if ($result.Success) {
            $message = "Concatenation complete!`n`nFiles processed: $($result.FilesProcessed)`nTotal tumors: $($result.TotalTumors)`nOutput: $outputPath"

            if ($result.Errors.Count -gt 0) {
                $message += "`n`nWarnings ($($result.Errors.Count) files skipped):`n"
                # Show first 5 errors max
                $errorsToShow = $result.Errors | Select-Object -First 5
                $message += ($errorsToShow -join "`n")
                if ($result.Errors.Count -gt 5) {
                    $message += "`n... and $($result.Errors.Count - 5) more"
                }
            }

            $message += "`n`nOpen newly created file?"

            $openResult = [System.Windows.Forms.MessageBox]::Show(
                $message,
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($openResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Load the newly created file
                if ($Controls -ne $null) {
                    Import-XmlFile -FilePath $outputPath -Controls $Controls
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
