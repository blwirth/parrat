# deduplicate-ui.ps1
# UI dialogs for deduplication features

function Show-DeduplicationPreview {
    param(
        [hashtable]$Result,
        [int]$OriginalCount,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$DedupType
    )

    $dedupedCount = $Result.IndicesToKeep.Count
    $removedCount = $OriginalCount - $dedupedCount
    $duplicateCount = $Result.Report.Count

    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Deduplication Preview - $DedupType"
    $previewForm.Width = 1400
    $previewForm.Height = 700
    $previewForm.StartPosition = "CenterScreen"
    $previewForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $previewForm.MaximizeBox = $false
    $previewForm.MinimizeBox = $false

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Original tumors: $OriginalCount | Will keep: $dedupedCount | Will remove: $removedCount duplicates | Duplicate groups: $duplicateCount"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # DataGridView for report
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 60)
    $grid.Size = New-Object System.Drawing.Size(1360, 500)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "AllCells"

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientKey", [string])
    [void]$table.Columns.Add("AllIndices", [string])
    [void]$table.Columns.Add("KeptIndex", [string])
    [void]$table.Columns.Add("RemovedIndices", [string])
    [void]$table.Columns.Add("Reason", [string])
    [void]$table.Columns.Add("DateReceived", [string])
    [void]$table.Columns.Add("Physician3", [string])

    foreach ($item in $Result.Report) {
        $row = $table.NewRow()
        $row["PatientKey"] = $item.PatientKey
        $row["AllIndices"] = $item.AllIndices
        $row["KeptIndex"] = $item.KeptIndex
        $row["RemovedIndices"] = $item.RemovedIndices
        $row["Reason"] = $item.Reason
        $row["DateReceived"] = $item.DateReceived
        $row["Physician3"] = $item.Physician3
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Buttons
    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = "Proceed with Deduplication"
    $btnProceed.Width = 200
    $btnProceed.Location = New-Object System.Drawing.Point(10, 580)
    $btnProceed.Anchor = 'Bottom,Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(220, 580)
    $btnCancel.Anchor = 'Bottom,Left'

    # Set CancelButton so ESC key and X button work properly
    $previewForm.CancelButton = $btnCancel

    # Proceed button handler
    $btnProceed.Add_Click({
        $previewForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $previewForm.Close()
    })

    # Cancel button handler
    $btnCancel.Add_Click({
        $previewForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $previewForm.Close()
    })

    # Handle form closing (X button) to ensure DialogResult is set
    $previewForm.Add_FormClosing({
        param($eventSender, $e)
        if ($eventSender.DialogResult -eq [System.Windows.Forms.DialogResult]::None) {
            $eventSender.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
    })

    # Add controls to form
    $previewForm.Controls.AddRange(@($lblSummary, $grid, $btnProceed, $btnCancel))

    $dialogResult = $previewForm.ShowDialog()

    # Only proceed if user clicked OK
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        # Map DedupType to file suffix
        $suffix = switch ($DedupType) {
            "TrueMatches" { "-ddtr" }
            "PrimaryKey"  { "-ddpk" }
            "PathReport"  { "-ddpr" }
            default       { "-dedup" }
        }

        # User clicked proceed - show the full report
        Show-DeduplicationReport `
            -Report $Result.Report `
            -IndicesToKeep $Result.IndicesToKeep `
            -OriginalCount $OriginalCount `
            -OriginalFilePath $OriginalFilePath `
            -XmlDoc $XmlDoc `
            -Tumors $Tumors `
            -FileSuffix $suffix
    }
    # If Cancel or closed, just return (do nothing)
    # Explicitly return nothing to avoid any return value issues
    return
}

function Show-DeduplicationReport {
    param(
        [array]$Report,
        [hashtable]$IndicesToKeep,
        [int]$OriginalCount,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [string]$FileSuffix = "-dedup"
    )

    $dedupedCount = $IndicesToKeep.Count
    $removedCount = $OriginalCount - $dedupedCount

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Deduplication Report"
    $reportForm.Width = 1400
    $reportForm.Height = 700
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Original tumors: $OriginalCount | Kept: $dedupedCount | Removed: $removedCount duplicates"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # DataGridView for report
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 60)
    $grid.Size = New-Object System.Drawing.Size(1360, 500)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "AllCells"

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientKey", [string])
    [void]$table.Columns.Add("AllIndices", [string])
    [void]$table.Columns.Add("KeptIndex", [string])
    [void]$table.Columns.Add("RemovedIndices", [string])
    [void]$table.Columns.Add("Reason", [string])
    [void]$table.Columns.Add("DateReceived", [string])
    [void]$table.Columns.Add("Physician3", [string])

    foreach ($item in $Report) {
        $row = $table.NewRow()
        $row["PatientKey"] = $item.PatientKey
        $row["AllIndices"] = $item.AllIndices
        $row["KeptIndex"] = $item.KeptIndex
        $row["RemovedIndices"] = $item.RemovedIndices
        $row["Reason"] = $item.Reason
        $row["DateReceived"] = $item.DateReceived
        $row["Physician3"] = $item.Physician3
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Buttons
    $btnSaveXml = New-Object System.Windows.Forms.Button
    $btnSaveXml.Text = "Save Deduped XML"
    $btnSaveXml.Width = 150
    $btnSaveXml.Location = New-Object System.Drawing.Point(10, 580)
    $btnSaveXml.Anchor = 'Bottom,Left'

    $btnSaveCsv = New-Object System.Windows.Forms.Button
    $btnSaveCsv.Text = "Save CSV Report"
    $btnSaveCsv.Width = 150
    $btnSaveCsv.Location = New-Object System.Drawing.Point(170, 580)
    $btnSaveCsv.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(330, 580)
    $btnClose.Anchor = 'Bottom,Left'

    # Save XML button handler
    $btnSaveXml.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName$FileSuffix.xml")

            Write-DedupedXml -XmlDoc $XmlDoc -Tumors $Tumors -IndicesToKeep $IndicesToKeep -OutputPath $outputPath

            [System.Windows.Forms.MessageBox]::Show(
                "Deduplicated XML saved to:`n$outputPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving XML: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Save CSV button handler
    $btnSaveCsv.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName$FileSuffix-report.csv")

            $Report | Export-Csv -Path $csvPath -NoTypeInformation

            [System.Windows.Forms.MessageBox]::Show(
                "CSV report saved to:`n$csvPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving CSV: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Close button handler
    $btnClose.Add_Click({
        $reportForm.Close()
    })

    # Add controls to form
    $reportForm.Controls.AddRange(@($lblSummary, $grid, $btnSaveXml, $btnSaveCsv, $btnClose))

    [void]$reportForm.ShowDialog()
}
