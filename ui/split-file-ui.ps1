# split-file-ui.ps1
# UI dialogs for file splitting features

function Show-SplitOptionsDialog {
    <#
    .SYNOPSIS
    Show modal dialog for split options

    .PARAMETER FilePath
    Source file path

    .PARAMETER TotalRecords
    Total number of records

    .PARAMETER LastNames
    Array of last names for distribution calculation

    .PARAMETER FileType
    'xml' or 'hl7'

    .OUTPUTS
    Hashtable with SplitCount and OutputDirectory, or $null if cancelled
    #>
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][int]$TotalRecords,
        [Parameter(Mandatory=$true)][array]$LastNames,
        [Parameter(Mandatory=$true)][string]$FileType
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $recordLabel = if ($FileType -eq 'xml') { "tumors" } else { "messages" }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Split File by Last Name"
    $dialog.Width = 550
    $dialog.Height = 380
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    # Source file label
    $lblSource = New-Object System.Windows.Forms.Label
    $lblSource.Location = New-Object System.Drawing.Point(15, 15)
    $lblSource.Size = New-Object System.Drawing.Size(500, 20)
    $lblSource.Text = "Source: $fileName"
    $lblSource.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    # Total records label
    $lblTotal = New-Object System.Windows.Forms.Label
    $lblTotal.Location = New-Object System.Drawing.Point(15, 40)
    $lblTotal.Size = New-Object System.Drawing.Size(500, 20)
    $lblTotal.Text = "Total $recordLabel : $TotalRecords"

    # Split count group box
    $grpSplit = New-Object System.Windows.Forms.GroupBox
    $grpSplit.Text = "Split into how many files?"
    $grpSplit.Location = New-Object System.Drawing.Point(15, 70)
    $grpSplit.Size = New-Object System.Drawing.Size(500, 60)

    # Radio buttons for split count
    $script:selectedSplitCount = 2

    $rdo2 = New-Object System.Windows.Forms.RadioButton
    $rdo2.Text = "2 files"
    $rdo2.Location = New-Object System.Drawing.Point(20, 25)
    $rdo2.Width = 70
    $rdo2.Checked = $true
    $rdo2.Tag = 2

    $rdo3 = New-Object System.Windows.Forms.RadioButton
    $rdo3.Text = "3 files"
    $rdo3.Location = New-Object System.Drawing.Point(110, 25)
    $rdo3.Width = 70
    $rdo3.Tag = 3

    $rdo4 = New-Object System.Windows.Forms.RadioButton
    $rdo4.Text = "4 files"
    $rdo4.Location = New-Object System.Drawing.Point(200, 25)
    $rdo4.Width = 70
    $rdo4.Tag = 4

    $rdo5 = New-Object System.Windows.Forms.RadioButton
    $rdo5.Text = "5 files"
    $rdo5.Location = New-Object System.Drawing.Point(290, 25)
    $rdo5.Width = 70
    $rdo5.Tag = 5

    $grpSplit.Controls.AddRange(@($rdo2, $rdo3, $rdo4, $rdo5))

    # Preview label
    $lblPreview = New-Object System.Windows.Forms.Label
    $lblPreview.Location = New-Object System.Drawing.Point(15, 140)
    $lblPreview.Size = New-Object System.Drawing.Size(500, 100)
    $lblPreview.Font = New-Object System.Drawing.Font("Consolas", 9)

    # Function to update preview
    $updatePreview = {
        param([int]$splitCount)

        $ranges = Get-AlphabetRanges -SplitCount $splitCount
        $distribution = Get-SplitDistribution -LastNames $LastNames -SplitCount $splitCount

        # For XML, distribution is by patient but we show tumor totals
        # For HL7, distribution is by message (same as total)
        $distLabel = if ($FileType -eq 'xml') {
            "patients"
        } else {
            $recordLabel
        }

        $previewLines = @("Estimated distribution (by $distLabel):")
        for ($i = 0; $i -lt $ranges.Count; $i++) {
            $range = $ranges[$i]
            $count = $distribution[$i]
            $pct = if ($LastNames.Count -gt 0) { [math]::Round(($count / $LastNames.Count) * 100, 1) } else { 0 }
            $previewLines += ("  {0}: ~{1} {2} ({3}%)" -f $range.Label, $count, $distLabel, $pct)
        }

        # Note about malformed records
        $malformedCount = 0
        foreach ($name in $LastNames) {
            if ([string]::IsNullOrWhiteSpace($name)) {
                $malformedCount++
            }
            else {
                $firstChar = $name.Trim().Substring(0, 1).ToUpperInvariant()
                if ($firstChar -lt 'A' -or $firstChar -gt 'Z') {
                    $malformedCount++
                }
            }
        }

        if ($malformedCount -gt 0) {
            $previewLines += ""
            $previewLines += "Note: $malformedCount $distLabel with missing/invalid last names"
            $previewLines += "      will be placed in the last file ($($ranges[-1].Label))"
        }

        $lblPreview.Text = $previewLines -join "`r`n"
    }

    # Initial preview
    & $updatePreview 2

    # Wire up radio button events
    $radioHandler = {
        param($eventSender, $e)
        if ($eventSender.Checked) {
            $script:selectedSplitCount = [int]$eventSender.Tag
            & $updatePreview $script:selectedSplitCount
        }
    }

    $rdo2.Add_CheckedChanged($radioHandler)
    $rdo3.Add_CheckedChanged($radioHandler)
    $rdo4.Add_CheckedChanged($radioHandler)
    $rdo5.Add_CheckedChanged($radioHandler)

    # Output directory selection
    $lblOutputDir = New-Object System.Windows.Forms.Label
    $lblOutputDir.Location = New-Object System.Drawing.Point(15, 250)
    $lblOutputDir.Size = New-Object System.Drawing.Size(100, 20)
    $lblOutputDir.Text = "Output folder:"

    $txtOutputDir = New-Object System.Windows.Forms.TextBox
    $txtOutputDir.Location = New-Object System.Drawing.Point(115, 247)
    $txtOutputDir.Size = New-Object System.Drawing.Size(320, 25)
    $txtOutputDir.Text = [System.IO.Path]::GetDirectoryName($FilePath)
    $txtOutputDir.ReadOnly = $true

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "Browse..."
    $btnBrowse.Location = New-Object System.Drawing.Point(440, 245)
    $btnBrowse.Width = 75
    $btnBrowse.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select output folder for split files"
        $folderDialog.SelectedPath = $txtOutputDir.Text

        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtOutputDir.Text = $folderDialog.SelectedPath
        }
    })

    # Buttons
    $btnSplit = New-Object System.Windows.Forms.Button
    $btnSplit.Text = "Split"
    $btnSplit.Width = 100
    $btnSplit.Location = New-Object System.Drawing.Point(330, 295)
    $btnSplit.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(440, 295)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@(
        $lblSource, $lblTotal, $grpSplit, $lblPreview,
        $lblOutputDir, $txtOutputDir, $btnBrowse,
        $btnSplit, $btnCancel
    ))
    $dialog.AcceptButton = $btnSplit
    $dialog.CancelButton = $btnCancel

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return @{
            SplitCount = $script:selectedSplitCount
            OutputDirectory = $txtOutputDir.Text
        }
    }

    return $null
}

function Start-SplitFile {
    <#
    .SYNOPSIS
    Main entry point for splitting a file
    Opens file dialog, scans file, shows options dialog, and performs split
    #>

    Add-Type -AssemblyName System.Windows.Forms

    # Open file dialog
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NAACCR/HL7 Files (*.xml;*.hl7)|*.xml;*.hl7|NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*"
    $ofd.Title = "Select file to split"

    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $filePath = $ofd.FileName
    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
    $fileType = if ($extension -eq ".hl7") { "hl7" } else { "xml" }

    # Show wait cursor
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor

    try {
        # Scan the file
        if ($fileType -eq "hl7") {
            $scanResult = Get-Hl7FileSplitInfo -FilePath $filePath

            if (-not $scanResult.Success) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Error scanning file:`n$($scanResult.Error)",
                    "Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }

            $totalRecords = $scanResult.TotalMessages
            $lastNames = $scanResult.MessageData | ForEach-Object { $_.LastName }
        }
        else {
            $scanResult = Get-XmlFileSplitInfo -FilePath $filePath

            if (-not $scanResult.Success) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Error scanning file:`n$($scanResult.Error)",
                    "Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }

            # Use tumor count as the total records (that's what we're actually splitting)
            $totalRecords = $scanResult.TotalTumors
            $lastNames = $scanResult.PatientData | ForEach-Object { $_.LastName }
        }

        if ($totalRecords -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No records found in file.",
                "No Records",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
    }
    finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }

    # Show options dialog
    $options = Show-SplitOptionsDialog `
        -FilePath $filePath `
        -TotalRecords $totalRecords `
        -LastNames $lastNames `
        -FileType $fileType

    if ($null -eq $options) {
        return
    }

    # Show wait cursor during split
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor

    try {
        # Perform the split
        if ($fileType -eq "hl7") {
            $splitResult = Split-Hl7File `
                -ScanResult $scanResult `
                -FilePath $filePath `
                -SplitCount $options.SplitCount `
                -OutputDirectory $options.OutputDirectory
        }
        else {
            $splitResult = Split-XmlFile `
                -ScanResult $scanResult `
                -FilePath $filePath `
                -SplitCount $options.SplitCount `
                -OutputDirectory $options.OutputDirectory
        }

        if (-not $splitResult.Success) {
            [System.Windows.Forms.MessageBox]::Show(
                "Error splitting file:`n$($splitResult.Error)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        # Show success message
        $null = Get-AlphabetRanges -SplitCount $options.SplitCount
        $successLines = @("File split successfully!")
        $successLines += ""
        $successLines += "Created files:"

        for ($i = 0; $i -lt $splitResult.OutputFiles.Count; $i++) {
            $file = $splitResult.OutputFiles[$i]
            $fileName = [System.IO.Path]::GetFileName($file.Path)

            if ($fileType -eq "xml") {
                $successLines += ("  {0}: {1} patients, {2} tumors" -f $fileName, $file.PatientCount, $file.TumorCount)
            }
            else {
                $successLines += ("  {0}: {1} messages" -f $fileName, $file.MessageCount)
            }
        }

        $successLines += ""
        $successLines += "Output folder:"
        $successLines += $options.OutputDirectory

        $openFolder = [System.Windows.Forms.MessageBox]::Show(
            ($successLines -join "`r`n") + "`r`n`r`nOpen output folder?",
            "Split Complete",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        if ($openFolder -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Process "explorer.exe" -ArgumentList "`"$($options.OutputDirectory)`""
        }
    }
    finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
}
