# assign-site-laterality-ui.ps1
# UI dialogs for site/laterality assignment

function Show-AssignmentReport {
    param(
        [array]$Report,
        [hashtable]$Assignments,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [int]$TumorsWithExistingSite = 0,
        [int]$TumorsWithoutSiteNotCoded = 0
    )

    # Count assignments
    $siteCount = 0
    $latCount = 0
    foreach ($assignment in $Assignments.Values) {
        if ($assignment.PrimarySite) { $siteCount++ }
        if ($assignment.Laterality) { $latCount++ }
    }

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Primary Site & Laterality Assignment Report"
    $reportForm.Width = 1600
    $reportForm.Height = 800
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 30)
    $lblSummary.Text = "To update: $($Assignments.Count) | Sites: $siteCount | Laterality: $latCount | Existing site: $TumorsWithExistingSite | Not coded: $TumorsWithoutSiteNotCoded"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # Filter checkboxes
    $chkWillUpdate = New-Object System.Windows.Forms.CheckBox
    $chkWillUpdate.Text = "Show: Will be updated"
    $chkWillUpdate.Checked = $true
    $chkWillUpdate.Location = New-Object System.Drawing.Point(10, 45)
    $chkWillUpdate.AutoSize = $true

    $chkNoSiteNoUpdate = New-Object System.Windows.Forms.CheckBox
    $chkNoSiteNoUpdate.Text = "Show: No site, not updated"
    $chkNoSiteNoUpdate.Checked = $true
    $chkNoSiteNoUpdate.Location = New-Object System.Drawing.Point(200, 45)
    $chkNoSiteNoUpdate.AutoSize = $true

    $chkHasSiteNoUpdate = New-Object System.Windows.Forms.CheckBox
    $chkHasSiteNoUpdate.Text = "Show: Has site, not updated"
    $chkHasSiteNoUpdate.Checked = $true
    $chkHasSiteNoUpdate.Location = New-Object System.Drawing.Point(400, 45)
    $chkHasSiteNoUpdate.AutoSize = $true

    # Split container for grid and text preview
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Location = New-Object System.Drawing.Point(10, 75)
    $splitContainer.Size = New-Object System.Drawing.Size(1560, 615)
    $splitContainer.Anchor = 'Top,Left,Right,Bottom'
    $splitContainer.Orientation = 'Horizontal'
    $splitContainer.SplitterDistance = 300

    # DataGridView for report (top)
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "AllCells"
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false

    # Build DataTable (full dataset)
    $fullTable = New-Object System.Data.DataTable
    [void]$fullTable.Columns.Add("TumorIndex", [int])
    [void]$fullTable.Columns.Add("PatientName", [string])
    [void]$fullTable.Columns.Add("CurrentSite", [string])
    [void]$fullTable.Columns.Add("ProposedSite", [string])
    [void]$fullTable.Columns.Add("CurrentLaterality", [string])
    [void]$fullTable.Columns.Add("ProposedLaterality", [string])
    [void]$fullTable.Columns.Add("SourceText", [string])
    [void]$fullTable.Columns.Add("Category", [string])

    foreach ($item in $Report) {
        $row = $fullTable.NewRow()
        $row["TumorIndex"] = $item.TumorIndex
        $row["PatientName"] = $item.PatientName
        $row["CurrentSite"] = $item.CurrentSite
        $row["ProposedSite"] = $item.ProposedSite
        $row["CurrentLaterality"] = $item.CurrentLaterality
        $row["ProposedLaterality"] = $item.ProposedLaterality
        $row["SourceText"] = $item.SourceText
        $row["Category"] = $item.Category
        [void]$fullTable.Rows.Add($row)
    }

    # Create filtered DataView
    $dataView = New-Object System.Data.DataView($fullTable)
    $grid.DataSource = $dataView

    # Hide Category column (after grid is bound)
    $hideCategoryColumn = {
        try {
            if ($null -ne $grid.Columns["Category"]) {
                $grid.Columns["Category"].Visible = $false
            }
        }
        catch {
            # Column not available yet, will be hidden by DataBindingComplete event
            $null = $_.Exception
        }
    }

    $grid.Add_DataBindingComplete($hideCategoryColumn)

    # Also try to hide it after form loads
    $reportForm.Add_Load({
        & $hideCategoryColumn
    })

    # Filter function
    $updateFilter = {
        $filterParts = @()

        if ($chkWillUpdate.Checked) {
            $filterParts += "Category = 'WillUpdate'"
        }
        if ($chkNoSiteNoUpdate.Checked) {
            $filterParts += "(Category = 'NoSite_NoMatch' OR Category = 'NoSite_NoText')"
        }
        if ($chkHasSiteNoUpdate.Checked) {
            $filterParts += "Category = 'HasSite_NoUpdate'"
        }

        if ($filterParts.Count -eq 0) {
            $dataView.RowFilter = "1=0"  # Show nothing
        } else {
            $dataView.RowFilter = "(" + ($filterParts -join ") OR (") + ")"
        }
    }

    # Attach filter handlers
    $chkWillUpdate.Add_CheckedChanged($updateFilter)
    $chkNoSiteNoUpdate.Add_CheckedChanged($updateFilter)
    $chkHasSiteNoUpdate.Add_CheckedChanged($updateFilter)

    # Apply initial filter
    & $updateFilter

    # RichTextBox for text field preview (bottom)
    $rtbPreview = New-Object System.Windows.Forms.RichTextBox
    $rtbPreview.Dock = 'Fill'
    $rtbPreview.ReadOnly = $true
    $rtbPreview.Font = New-Object System.Drawing.Font("Consolas", 9)
    $rtbPreview.WordWrap = $true

    # Add to split container
    $splitContainer.Panel1.Controls.Add($grid)
    $splitContainer.Panel2.Controls.Add($rtbPreview)

    # Buttons
    $btnSaveXml = New-Object System.Windows.Forms.Button
    $btnSaveXml.Text = "Save Assigned XML"
    $btnSaveXml.Width = 150
    $btnSaveXml.Location = New-Object System.Drawing.Point(10, 710)
    $btnSaveXml.Anchor = 'Bottom,Left'

    $btnSaveCsv = New-Object System.Windows.Forms.Button
    $btnSaveCsv.Text = "Save CSV Report"
    $btnSaveCsv.Width = 150
    $btnSaveCsv.Location = New-Object System.Drawing.Point(170, 710)
    $btnSaveCsv.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(330, 710)
    $btnClose.Anchor = 'Bottom,Left'

    # Grid selection handler - show text fields
    $grid.Add_SelectionChanged({
        if ($grid.SelectedRows.Count -eq 0) { return }

        $selectedRow = $grid.SelectedRows[0]
        $tumorIndex = [int]$selectedRow.Cells["TumorIndex"].Value - 1

        if ($tumorIndex -lt 0 -or $tumorIndex -ge $Tumors.Count) { return }

        $tumor = $Tumors[$tumorIndex]
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
        $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

        $rtbPreview.Clear()

        # Show text fields
        $textFieldIds = @(
            "textDxProcLabTests",
            "textDxProcPath",
            "textDxProcPe",
            "textHistologyTitle",
            "textPrimarySiteTitle"
        )

        foreach ($textId in $textFieldIds) {
            $node = $tumor.SelectSingleNode("./n:Item[@naaccrId='$textId']", $nsMgr)
            if ($null -ne $node) {
                $rtbPreview.SelectionFont = Get-BoldFont $rtbPreview.Font
                $rtbPreview.AppendText("=== $textId ===`r`n")
                $rtbPreview.SelectionFont = $rtbPreview.Font

                $value = $node.InnerText
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $rtbPreview.AppendText("(no text)`r`n")
                }
                else {
                    $rtbPreview.AppendText("$value`r`n")
                }

                $rtbPreview.AppendText("`r`n")
            }
        }
    })

    # Save XML button handler
    $btnSaveXml.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-psite.xml")

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
            $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

            Write-AssignedXml -XmlDoc $XmlDoc -Tumors $Tumors -Assignments $Assignments -NsMgr $nsMgr -OutputPath $outputPath

            [System.Windows.Forms.MessageBox]::Show(
                "Assigned XML saved to:`n$outputPath",
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
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-assignment-report.csv")

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
    $reportForm.Controls.AddRange(@($lblSummary, $chkWillUpdate, $chkNoSiteNoUpdate, $chkHasSiteNoUpdate, $splitContainer, $btnSaveXml, $btnSaveCsv, $btnClose))

    [void]$reportForm.ShowDialog()
}
