. "$PSScriptRoot\xml-helpers.ps1"
. "$PSScriptRoot\xml-viewer.ps1"
. "$PSScriptRoot\diff.ps1"
. "$PSScriptRoot\deduplicate.ps1"
. "$PSScriptRoot\assign-site-laterality.ps1"
. "$PSScriptRoot\assign-facility.ps1"
. "$PSScriptRoot\concatenate-xml.ps1"
. "$PSScriptRoot\concatenate-hl7.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form = $form[0]  # ensure scalar type, not array
$form.Text   = "NAACCR XML Viewer"
$form.StartPosition = "CenterScreen"
$form.WindowState   = "Maximized"

# Top nav
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open XML..."
$btnOpen.Width = 100
$btnOpen.Location = New-Object System.Drawing.Point(10, 10)

$btnDiff = New-Object System.Windows.Forms.Button
$btnDiff.Text = "Diff"
$btnDiff.Width = 100
$btnDiff.Location = New-Object System.Drawing.Point(120, 10)

$btnXml = New-Object System.Windows.Forms.Button
$btnXml.Text = "Show Raw XML"
$btnXml.Width = 100
$btnXml.Location = New-Object System.Drawing.Point(230, 10)

$btnDedup = New-Object System.Windows.Forms.Button
$btnDedup.Text = "Deduplicate"
$btnDedup.Width = 100
$btnDedup.Location = New-Object System.Drawing.Point(340, 10)

$btnAssign = New-Object System.Windows.Forms.Button
$btnAssign.Text = "Assign Site/Lat"
$btnAssign.Width = 100
$btnAssign.Location = New-Object System.Drawing.Point(450, 10)

$btnFacility = New-Object System.Windows.Forms.Button
$btnFacility.Text = "Assign Facility"
$btnFacility.Width = 100
$btnFacility.Location = New-Object System.Drawing.Point(560, 10)

$btnConcatenateXml = New-Object System.Windows.Forms.Button
$btnConcatenateXml.Text = "Concatenate XMLs"
$btnConcatenateXml.Width = 120
$btnConcatenateXml.Location = New-Object System.Drawing.Point(670, 10)

$btnConcatenateHl7 = New-Object System.Windows.Forms.Button
$btnConcatenateHl7.Text = "Concatenate HL7s"
$btnConcatenateHl7.Width = 120
$btnConcatenateHl7.Location = New-Object System.Drawing.Point(800, 10)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(930, 15)
$lblStatus.Text = "No file loaded"

# Bottom nav
$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "<"
$btnPrev.Width = 40
$btnPrev.Location = New-Object System.Drawing.Point(10, 980)
$btnPrev.Enabled = $false

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = ">"
$btnNext.Width = 40
$btnNext.Location = New-Object System.Drawing.Point(60, 980)
$btnNext.Enabled = $false

$lblIndex = New-Object System.Windows.Forms.Label
$lblIndex.AutoSize = $true
$lblIndex.Location = New-Object System.Drawing.Point(130, 980)
$lblIndex.Text = ""

# --- Main resizable area (panel + split containers) ---

# Panel to host the split containers, leaving room for top buttons and bottom nav
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Location = New-Object System.Drawing.Point(10, 40)
# will be redrawn to fit screen below but give initial size
$mainPanel.Size     = New-Object System.Drawing.Size(1000, 800)
$mainPanel.Anchor   = 'Top,Left,Right,Bottom'

# Outer split container: left (grid) | right (inner split: path + items)
$splitOuter = New-Object System.Windows.Forms.SplitContainer
$splitOuter.Dock = 'Fill'
$splitOuter.Orientation = 'Vertical'
$splitOuter.IsSplitterFixed = $false
$splitOuter.Panel1MinSize = 200

# Inner split container: middle (path text) | right (other items)
$splitInner = New-Object System.Windows.Forms.SplitContainer
$splitInner.Dock = 'Fill'
$splitInner.Orientation = 'Vertical'
$splitInner.IsSplitterFixed = $false
$splitInner.Panel1MinSize = 300

$form.Add_Shown({
    param($sender, $e)

    # Adjust main panel to fit current client area
    $mainPanel.Size = New-Object System.Drawing.Size(
        [int]($sender.ClientSize.Width  - 20),
        [int]($sender.ClientSize.Height - 100)  # leave some space at the bottom
    )

    # Set splitter distances as proportions
    $splitOuter.SplitterDistance = [int]($splitOuter.Width * 0.20)
    $splitInner.SplitterDistance = [int]($splitInner.Width * 0.55)
})

# Navigation grid (left column)
$gridNav = New-Object System.Windows.Forms.DataGridView
$gridNav.Dock = 'Fill'
$gridNav.AllowUserToAddRows = $false
$gridNav.AllowUserToDeleteRows = $false
$gridNav.RowHeadersVisible = $false

$table = New-Object System.Data.DataTable
[void]$table.Columns.Add("Index", [int])
[void]$table.Columns.Add("nameLast", [string])
[void]$table.Columns.Add("nameFirst", [string])
[void]$table.Columns.Add("dateOfDiagnosis", [string])
[void]$table.Columns.Add("pathReportNumber1", [string])

# Bind table BEFORE re-setting selection-related properties
$gridNav.DataSource = $table

# Now enforce multi-select
$gridNav.ReadOnly = $true
$gridNav.MultiSelect = $true
$gridNav.SelectionMode = 'FullRowSelect'

# Middle column: pathology text fields
$rtbPath = New-Object System.Windows.Forms.RichTextBox
$rtbPath.Multiline = $true
$rtbPath.ScrollBars = "Both"
$rtbPath.WordWrap = $true
$rtbPath.ReadOnly = $true
$rtbPath.Font = New-Object System.Drawing.Font("Consolas", 10)
$rtbPath.Dock = 'Fill'

# Right column: other patient/tumor items
$rtbItems = New-Object System.Windows.Forms.RichTextBox
$rtbItems.Multiline = $true
$rtbItems.ScrollBars = "Both"
$rtbItems.WordWrap = $true
$rtbItems.ReadOnly = $true
$rtbItems.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbItems.Dock = 'Fill'

# Wire up split containers
$splitOuter.Panel1.Controls.Add($gridNav)
$splitInner.Panel1.Controls.Add($rtbPath)
$splitInner.Panel2.Controls.Add($rtbItems)
$splitOuter.Panel2.Controls.Add($splitInner)

$mainPanel.Controls.Add($splitOuter)

# Add everything to the form
$form.Controls.AddRange(@(
    $btnOpen,
    $btnDiff,
    $btnXml,
	$btnDedup,
	$btnAssign,
	$btnFacility,
	$btnConcatenateXml,
	$btnConcatenateHl7,
    $lblStatus,
    $mainPanel,
    $btnPrev,
    $btnNext,
    $lblIndex
))

# State
$script:Tumors          = @()
$script:CurrentIndex    = -1
$script:NsMgr           = $null
$script:NavTable        = $null
$script:XmlDoc          = $null
$script:CurrentFilePath = $null

function Show-Tumor {
    param(
        [int]$Index
    )

    if ($script:Tumors.Count -eq 0) { return }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) { return }

    $script:CurrentIndex = $Index
    $tumor = $script:Tumors[$Index]

    # Clear text boxes
    $rtbPath.Clear()
    $rtbItems.Clear()

    # Select the corresponding row in the grid based on the Index column value
    $targetIndexValue = $Index + 1
    $gridNav.ClearSelection()
    foreach ($row in $gridNav.Rows) {
        if ($row.Cells["Index"].Value -eq $targetIndexValue) {
            $row.Selected = $true
            $gridNav.CurrentCell = $row.Cells[0]
            break
        }
    }

    # Determine patient node
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    # Middle column: pathology text fields from the tumor
    $tumorItemsAll = $tumor.SelectNodes("./n:Item", $script:NsMgr)

    foreach ($textId in $script:TextFieldIds) {
        $node = $tumor.SelectSingleNode("./n:Item[@naaccrId='$textId']", $script:NsMgr)
        if ($node -ne $null) {
            Add-LineToRichTextBox $rtbPath ("=== {0} ===" -f $textId) $true

            $value = $node.InnerText
            if ([string]::IsNullOrWhiteSpace($value)) {
                Add-LineToRichTextBox $rtbPath "(no text)"
            }
            else {
                $lines = $value -split "(`r`n|`n|`r)"
                foreach ($line in $lines) {
                    Add-LineToRichTextBox $rtbPath $line
                }
            }

            Add-LineToRichTextBox $rtbPath ""  # single blank line between sections
        }
    }

    # Right column: patient-level items, then tumor-level items (excluding text field IDs)
    Add-LineToRichTextBox $rtbItems ("Tumor {0} of {1}" -f ($Index + 1), $script:Tumors.Count) $true
    Add-LineToRichTextBox $rtbItems ""

    if ($patient -ne $null) {
        $patientItems = $patient.SelectNodes("./n:Item", $script:NsMgr)
        if ($patientItems -and $patientItems.Count -gt 0) {
            Add-LineToRichTextBox $rtbItems "=== PATIENT ITEMS ===" $true
            foreach ($item in $patientItems) {
                $id    = $item.GetAttribute("naaccrId")
                $value = $item.InnerText
                $isBold = $script:BoldIds -contains $id
                Add-LineToRichTextBox $rtbItems ("{0}: {1}" -f $id, $value) $isBold
            }
            Add-LineToRichTextBox $rtbItems ""
        }
    }

    $tumorItems = @()
    if ($tumorItemsAll -and $tumorItemsAll.Count -gt 0) {
        foreach ($item in $tumorItemsAll) {
            $id = $item.GetAttribute("naaccrId")
            if ($script:TextFieldIds -notcontains $id) {
                $tumorItems += $item
            }
        }
    }

    if ($tumorItems -and $tumorItems.Count -gt 0) {
        Add-LineToRichTextBox $rtbItems "=== TUMOR ITEMS ===" $true
        foreach ($item in $tumorItems) {
            $id    = $item.GetAttribute("naaccrId")
            $value = $item.InnerText
            $isBold = $script:BoldIds -contains $id
            Add-LineToRichTextBox $rtbItems ("{0}: {1}" -f $id, $value) $isBold
        }
    }

    $lblIndex.Text = "Tumor {0} of {1}" -f ($Index + 1), $script:Tumors.Count
    $btnPrev.Enabled = ($Index -gt 0)
    $btnNext.Enabled = ($Index -lt ($script:Tumors.Count - 1))
}

function Show-TumorDiff {
    param(
        [int]$IndexA,
        [int]$IndexB
    )

    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Diff Tumors")
        return
    }

    $mapA = Get-NaaccrItemMap -Index $IndexA -Tumors $script:Tumors -NsMgr $script:NsMgr
    $mapB = Get-NaaccrItemMap -Index $IndexB -Tumors $script:Tumors -NsMgr $script:NsMgr

    # Combined key set
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $mapA.Keys) { [void]$keys.Add($k) }
    foreach ($k in $mapB.Keys) { [void]$keys.Add($k) }

    # Build DataTable for diff
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Scope",  [string]) # Patient/Tumor
    [void]$table.Columns.Add("naaccrId", [string])
    [void]$table.Columns.Add("ValueA", [string])
    [void]$table.Columns.Add("ValueB", [string])
    [void]$table.Columns.Add("Status", [string]) # Same, Different, Only A, Only B

    foreach ($k in $keys) {
        $parts = $k.Split('|', 2)
        $scopeCode = $parts[0]
        $id        = $parts[1]

        $scope = if ($scopeCode -eq "P") { "Patient" } else { "Tumor" }

        $hasA = $mapA.ContainsKey($k)
        $hasB = $mapB.ContainsKey($k)

        $valA = if ($hasA) { $mapA[$k] } else { "" }
        $valB = if ($hasB) { $mapB[$k] } else { "" }

        if (-not $hasA -and -not $hasB) { continue }

        if ($hasA -and $hasB) {
            if ($valA -eq $valB) {
                $status = "Same"
            }
            else {
                $status = "Different"
            }
        }
        elseif ($hasA) {
            $status = "Only A"
        }
        else {
            $status = "Only B"
        }

        $row = $table.NewRow()
        $row["Scope"]   = $scope
        $row["naaccrId"] = $id
        $row["ValueA"]  = $valA
        $row["ValueB"]  = $valB
        $row["Status"]  = $status
        [void]$table.Rows.Add($row)
    }

    # Diff form
	$labelA = Get-TumorLabel -Index $IndexA
	$labelB = Get-TumorLabel -Index $IndexB

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text   = "Diff: $labelA  VS  $labelB"
    $diffForm.Width  = 1600
    $diffForm.Height = 800
    $diffForm.StartPosition = "CenterScreen"

    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Dock = 'Fill'
    $gridDiff.ReadOnly = $true
    $gridDiff.AutoSizeColumnsMode = "Fill"
    $gridDiff.RowHeadersVisible = $false
    $gridDiff.AllowUserToAddRows = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.DataSource = $table

    # Color rows by Status
    $gridDiff.add_RowPrePaint({
        param($sender, $e)
        $row = $sender.Rows[$e.RowIndex]
        $status = [string]$row.Cells["Status"].Value
        switch ($status) {
            "Same"      { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White }
            "Different" { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow }
            "Only A"    { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightBlue }
            "Only B"    { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen }
        }
    })

    $diffForm.Controls.Add($gridDiff)
    [void]$diffForm.ShowDialog()
}

$btnOpen.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
    $ofd.Title  = "Select NAACCR XML file"

    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.XmlResolver = $null
            $xml.Load($ofd.FileName)

            $script:XmlDoc = $xml  # keep full document for grabbing the file-level headers, e.g., the namespace 
			$script:CurrentFilePath = $ofd.FileName # storing filepath for deduplication

            $nsUri = $xml.DocumentElement.NamespaceURI
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
            $nsMgr.AddNamespace("n", $nsUri)

            $script:NsMgr   = $nsMgr
            $script:Tumors  = $xml.SelectNodes("//n:Tumor", $nsMgr)
            $script:CurrentIndex = -1

            if ($script:Tumors.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No <Tumor> elements found in this file.", "No Tumors")
                $lblStatus.Text = "No tumors found"
                $rtbPath.Clear()
                $rtbItems.Clear()
                $gridNav.DataSource = $null
                $btnPrev.Enabled = $false
                $btnNext.Enabled = $false
                $lblIndex.Text   = ""
            }
            else {
                $fileName = [System.IO.Path]::GetFileName($ofd.FileName)
                $lblStatus.Text = "Loaded: {0} (Tumors: {1})" -f $fileName, $script:Tumors.Count

                # Build navigation table
                $table = New-Object System.Data.DataTable
                [void]$table.Columns.Add("Index",           [int])
                [void]$table.Columns.Add("nameLast",        [string])
                [void]$table.Columns.Add("nameFirst",       [string])
                [void]$table.Columns.Add("dateOfDiagnosis", [string])
                [void]$table.Columns.Add("pathReportNumber1", [string])

                for ($i = 0; $i -lt $script:Tumors.Count; $i++) {
                    $tumor   = $script:Tumors[$i]
                    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

                    $nameLast  = ""
                    $nameFirst = ""
                    $dxDate    = ""
                    $pathReportNumber1 = ""

                    if ($patient -ne $null) {
                        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $script:NsMgr)
                        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $script:NsMgr)

                        if ($nlNode) { $nameLast  = $nlNode.InnerText }
                        if ($nfNode) { $nameFirst = $nfNode.InnerText }
                    }

                    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $script:NsMgr)
                    if ($dxNode) { $dxDate = $dxNode.InnerText }
                    
                    $pathNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $script:NsMgr)
                    if ($pathNode) { $pathReportNumber1 = $pathNode.InnerText }

                    $row = $table.NewRow()
                    $row["Index"]             = $i + 1
                    $row["nameLast"]          = $nameLast
                    $row["nameFirst"]         = $nameFirst
                    $row["pathReportNumber1"] = $pathReportNumber1
                    $row["dateOfDiagnosis"]   = $dxDate

                    [void]$table.Rows.Add($row)
                }

                $script:NavTable = $table
                $gridNav.DataSource = $table

                # Allow sorting by clicking column headers
                foreach ($col in $gridNav.Columns) {
                    $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
                }

                Show-Tumor -Index 0
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Error loading XML: {0}" -f $_.Exception.Message, "Error")
        }
    }
})

# Grid row selection -> show that tumor (using Index column, not row position)
$gridNav.Add_SelectionChanged({
    if ($script:Tumors.Count -eq 0) { return }

    # Only navigate when exactly one row is selected.
    # If user selects multiple rows (Ctrl/Shift), do nothing here.
    if ($gridNav.SelectedRows.Count -ne 1) { return }

    $selectedRow  = $gridNav.SelectedRows[0]
    $indexValObj  = $selectedRow.Cells["Index"].Value
    if ($indexValObj -eq $null) { return }

    $tumorIndex = [int]$indexValObj - 1

    if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) { return }
    if ($tumorIndex -eq $script:CurrentIndex) { return }

    Show-Tumor -Index $tumorIndex
})

# Button handlers
$btnPrev.Add_Click({
    if ($script:CurrentIndex -gt 0) {
        Show-Tumor -Index ($script:CurrentIndex - 1)
    }
})

$btnNext.Add_Click({
    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt ($script:Tumors.Count - 1)) {
        Show-Tumor -Index ($script:CurrentIndex + 1)
    }
})

$btnXml.Add_Click({
    if ($script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Show XML")
        return
    }

    if ($gridNav.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a row in the grid first.", "Show XML")
        return
    }

    # Use the first selected row for XML display
    $row = $gridNav.SelectedRows[0]
    $val = $row.Cells["Index"].Value
    if ($val -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Unable to determine index for selected row.", "Show XML")
        return
    }

    $idx = [int]$val - 1
    Show-RawXmlForTumor -Index $idx -Tumors $script:Tumors -NsMgr $script:NsMgr -XmlDoc $script:XmlDoc
})

$btnDiff.Add_Click({
    if ($script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Diff")
        return
    }

    $rows = $gridNav.SelectedRows
    if ($rows.Count -ne 2) {
        [System.Windows.Forms.MessageBox]::Show("Please select exactly two rows in the grid to compare.", "Diff")
        return
    }

    $indexVals = @()
    foreach ($r in $rows) {
        $val = $r.Cells["Index"].Value
        if ($val -ne $null) {
            $indexVals += ([int]$val)
        }
    }

    if ($indexVals.Count -ne 2) {
        [System.Windows.Forms.MessageBox]::Show("Unable to determine both indices for comparison.", "Diff")
        return
    }

    $idxA = $indexVals[0] - 1
    $idxB = $indexVals[1] - 1

    if ($idxA -lt 0 -or $idxA -ge $script:Tumors.Count -or
        $idxB -lt 0 -or $idxB -ge $script:Tumors.Count) {
        [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
        return
    }

    Show-NaaccrTumorDiff -IndexA $idxA -IndexB $idxB
})

$btnDedup.Add_Click({
	if ($script:Tumors.Count -eq 0) {
		[System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Deduplicate")
		return
	}
	
	if (-not $script:CurrentFilePath) {
		[System.Windows.Forms.MessageBox]::Show("No file path available.", "Deduplicate")
		return
	}
	
	try {
		$lblStatus.Text = "Analyzing duplicates..."
		$form.Refresh()
		
		# Run dedup analysis
		$result = Get-Duplicates -Tumors $script:Tumors -NsMgr $script:NsMgr
		
		$lblStatus.Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
		
		if ($result.Report.Count -eq 0) {
			[System.Windows.Forms.MessageBox]::Show(
			"No duplicates found!",
			"Deduplication complete",
			[System.Windows.Forms.MessageBoxButtons]::OK,
			[System.Windows.Forms.MessageBoxIcon]::Information
			)
		}
		else {
			# Show Report
			Show-DeduplicationReport `
				-Report $result.Report `
				-IndicesToKeep $result.IndicesToKeep `
				-OriginalCount $script:Tumors.Count `
				-OriginalFilePath $script:CurrentFilePath `
				-XmlDoc $script:XmlDoc `
				-Tumors $script:Tumors 
			}
		}
		catch {
			[System.Windows.Forms.MessageBox]::Show("Error during deduplication: $($_.Exception.Message)",
			"Error", 
			[System.Windows.Forms.MessageBoxButtons]::OK,
			[System.Windows.Forms.MessageBoxIcon]::Error
			)
			$lblStatus.Text = "Error during deduplication"
		}
})

$btnAssign.Add_Click({
    if ($script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Assign Site/Lat")
        return
    }
    
    try {
        $lblStatus.Text = "Analyzing missing fields..."
        $form.Refresh()
        
        # Run analysis
        $result = Get-MissingFields -Tumors $script:Tumors -NsMgr $script:NsMgr
        
        $lblStatus.Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
        
        if ($result.Report.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "All tumors have primarySite and laterality assigned!",
                "Assignment complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        else {
            # Show preview report
            Show-AssignmentReport `
                -Report $result.Report `
                -Assignments $result.Assignments `
                -OriginalFilePath $script:CurrentFilePath `
                -XmlDoc $script:XmlDoc `
                -Tumors $script:Tumors
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error during analysis: $($_.Exception.Message)",
            "Error"
        )
        $lblStatus.Text = "Error during analysis"
    }
})

$btnFacility.Add_Click({
    if ($script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Assign Facility")
        return
    }
    
    if (-not $script:CurrentFilePath) {
        [System.Windows.Forms.MessageBox]::Show("No file path available.", "Assign Facility")
        return
    }
    
    try {
        # Try to extract facility number from filename
        $facilityNum = Get-FacilityFromFilename -FilePath $script:CurrentFilePath
        
        # If not found in filename, prompt user
        if (-not $facilityNum) {
            $inputForm = New-Object System.Windows.Forms.Form
            $inputForm.Text = "Enter Facility Number"
            $inputForm.Width = 350
            $inputForm.Height = 170
            $inputForm.StartPosition = "CenterScreen"
            
            $lblPrompt = New-Object System.Windows.Forms.Label
            $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
            $lblPrompt.Size = New-Object System.Drawing.Size(320, 60)
            $lblPrompt.Text = "No 7-digit facility number found in filename.`nPlease enter the facility number (will be padded to 10 digits):"
            
            $txtFacility = New-Object System.Windows.Forms.TextBox
            $txtFacility.Location = New-Object System.Drawing.Point(10, 70)
            $txtFacility.Width = 320
            
            $btnOk = New-Object System.Windows.Forms.Button
            $btnOk.Text = "OK"
            $btnOk.Location = New-Object System.Drawing.Point(150, 100)
            $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
            
            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = "Cancel"
            $btnCancel.Location = New-Object System.Drawing.Point(230, 100)
            $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            
            $inputForm.Controls.AddRange(@($lblPrompt, $txtFacility, $btnOk, $btnCancel))
            $inputForm.AcceptButton = $btnOk
            $inputForm.CancelButton = $btnCancel
            
            $result = $inputForm.ShowDialog()
            
            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                $userInput = $txtFacility.Text.Trim()
                
                # Validate input is numeric and has reasonable length
                if ($userInput -match '^\d+$') {
                    $facilityNum = $userInput.PadLeft(10, '0')
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Invalid facility number. Must be numeric.",
                        "Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    return
                }
            }
            else {
                # User cancelled
                return
            }
        }
        
        $lblStatus.Text = "Analyzing facilities numbers..."
        $form.Refresh()
        
        # Run analysis
        $result = Get-FacilityAssignments -Tumors $script:Tumors -NsMgr $script:NsMgr -FacilityNumber $facilityNum
        
        $lblStatus.Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
        
        if ($result.Report.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "All tumors already have valid facility numbers!",
                "Assignment complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        else {
            # Show preview report
            Show-FacilityAssignmentReport `
                -Report $result.Report `
                -Assignments $result.Assignments `
                -FacilityNumber $facilityNum `
                -OriginalFilePath $script:CurrentFilePath `
                -XmlDoc $script:XmlDoc `
                -Tumors $script:Tumors
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error during facility assignment: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $lblStatus.Text = "Error during facility assignment"
    }
})

$btnConcatenateXml.Add_Click({
    Start-ConcatenateXml
})

$btnConcatenateHl7.Add_Click({
    Start-ConcatenateHl7
})

[void]$form.ShowDialog()
