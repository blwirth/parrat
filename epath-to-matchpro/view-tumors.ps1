. "$PSScriptRoot\diff.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text   = "NAACCR XML Viewer"
$form.Width  = 1800
$form.Height = 1030
$form.StartPosition = "CenterScreen"

# Open file button
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open XML..."
$btnOpen.Width = 100
$btnOpen.Location = New-Object System.Drawing.Point(10, 10)

# Diff button
$btnDiff = New-Object System.Windows.Forms.Button
$btnDiff.Text = "Diff selected"
$btnDiff.Width = 120
$btnDiff.Location = New-Object System.Drawing.Point(120, 10)

# Show XML button
$btnXml = New-Object System.Windows.Forms.Button
$btnXml.Text = "Show XML"
$btnXml.Width = 100
$btnXml.Location = New-Object System.Drawing.Point(250, 10)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(370, 15)
$lblStatus.Text = "No file loaded"

# Navigation buttons and label (bottom left)
$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "<"
$btnPrev.Width = 40
$btnPrev.Location = New-Object System.Drawing.Point(10, 950)
$btnPrev.Enabled = $false

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = ">"
$btnNext.Width = 40
$btnNext.Location = New-Object System.Drawing.Point(60, 950)
$btnNext.Enabled = $false

$lblIndex = New-Object System.Windows.Forms.Label
$lblIndex.AutoSize = $true
$lblIndex.Location = New-Object System.Drawing.Point(130, 955)
$lblIndex.Text = ""

# --- Main resizable area (panel + split containers) -------------------------

# Panel to host the split containers, leaving room for top buttons and bottom nav
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Location = New-Object System.Drawing.Point(10, 40)
$mainPanel.Size     = New-Object System.Drawing.Size(($form.Width - 40), 900)
$mainPanel.Anchor   = 'Top,Left,Right,Bottom'

# Outer split container: left (grid) | right (inner split: path + items)
$splitOuter = New-Object System.Windows.Forms.SplitContainer
$splitOuter.Dock = 'Fill'
$splitOuter.Orientation = 'Vertical'
$splitOuter.SplitterDistance = 350         # initial width of left column
$splitOuter.IsSplitterFixed = $false
$splitOuter.Panel1MinSize = 200
# No Panel2MinSize here; let Windows handle it

# Inner split container: middle (path text) | right (other items)
$splitInner = New-Object System.Windows.Forms.SplitContainer
$splitInner.Dock = 'Fill'
$splitInner.Orientation = 'Vertical'
$splitInner.SplitterDistance = 980         # initial width of middle column
$splitInner.IsSplitterFixed = $false
$splitInner.Panel1MinSize = 300
# No Panel2MinSize here either

# Navigation grid (left column)
$gridNav = New-Object System.Windows.Forms.DataGridView
$gridNav.Dock = 'Fill'
$gridNav.ReadOnly = $true
$gridNav.SelectionMode = "FullRowSelect"
$gridNav.MultiSelect = $true      # allow multi-select for diff
$gridNav.AllowUserToAddRows = $false
$gridNav.AllowUserToDeleteRows = $false
$gridNav.AllowUserToResizeRows = $false
$gridNav.AllowUserToResizeColumns = $true
$gridNav.RowHeadersVisible = $false
$gridNav.AutoSizeColumnsMode = "Fill"

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
    $lblStatus,
    $mainPanel,
    $btnPrev,
    $btnNext,
    $lblIndex
))

# State
$script:Tumors       = @()
$script:CurrentIndex = -1
$script:NsMgr        = $null
$script:NavTable     = $null
$script:XmlDoc       = $null

# NAACCR IDs to bold in the right column
$script:BoldIds = @(
    "nameFirst",
    "nameLast",
    "nameMiddle",
    "dateOfBirth",
    "dateOfDiagnosis",
    "primarySite",
    "laterality"
)

# NAACCR IDs that are pathology text fields (middle column)
$script:TextFieldIds = @(
    "textDxProcLabTests",
    "textDxProcPath",
    "textDxProcPe",
    "textHistologyTitle"
)

function Add-LineToRichTextBox {
    param(
        [System.Windows.Forms.RichTextBox]$Box,
        [string]$Text,
        [bool]$Bold = $false
    )

    $Box.SelectionStart  = $Box.TextLength
    $Box.SelectionLength = 0

    if ($Bold) {
        $Box.SelectionFont = New-Object System.Drawing.Font(
            $Box.Font.FontFamily,
            $Box.Font.Size,
            [System.Drawing.FontStyle]::Bold
        )
    }
    else {
        $Box.SelectionFont = $Box.Font
    }

    $Box.AppendText($Text + "`r`n")
}

function Get-TumorLabel {
    param(
        [int]$Index
    )

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $nameLast  = ""
    $nameFirst = ""
    $dxDate    = ""

    if ($patient -ne $null) {
        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $script:NsMgr)
        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $script:NsMgr)
        if ($nlNode) { $nameLast  = $nlNode.InnerText }
        if ($nfNode) { $nameFirst = $nfNode.InnerText }
    }

    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $script:NsMgr)
    if ($dxNode) { $dxDate = $dxNode.InnerText }

    return "Idx {0} - {1}, {2} - Dx {3}" -f ($Index + 1), $nameLast, $nameFirst, $dxDate
}

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

function Get-NaaccrItemMap {
    param(
        [int]$Index
    )

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $map = @{}

    # Patient items
    if ($patient -ne $null) {
        $pItems = $patient.SelectNodes("./n:Item", $script:NsMgr)
        foreach ($item in $pItems) {
            $id  = $item.GetAttribute("naaccrId")
            $val = $item.InnerText
            # Key format: "P|naaccrId"
            $map["P|$id"] = $val
        }
    }

    # Tumor items
    $tItems = $tumor.SelectNodes("./n:Item", $script:NsMgr)
    foreach ($item in $tItems) {
        $id  = $item.GetAttribute("naaccrId")
        $val = $item.InnerText
        # Key format: "T|naaccrId"
        $map["T|$id"] = $val
    }

    return $map
}

function Show-TumorDiff {
    param(
        [int]$IndexA,
        [int]$IndexB
    )

    $mapA = Get-NaaccrItemMap -Index $IndexA
    $mapB = Get-NaaccrItemMap -Index $IndexB

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

                    if ($patient -ne $null) {
                        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $script:NsMgr)
                        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $script:NsMgr)

                        if ($nlNode) { $nameLast  = $nlNode.InnerText }
                        if ($nfNode) { $nameFirst = $nfNode.InnerText }
                    }

                    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $script:NsMgr)
                    if ($dxNode) { $dxDate = $dxNode.InnerText }
					
					$dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $script:NsMgr)
                    if ($dxNode) { $pathReportNumber1 = $dxNode.InnerText }

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
    if ($gridNav.SelectedRows.Count -eq 0) { return }

    # Use the first selected row for main viewer navigation
    $selectedRow = $gridNav.SelectedRows[0]
    $indexValObj = $selectedRow.Cells["Index"].Value
    if ($indexValObj -eq $null) { return }

    $tumorIndex = [int]$indexValObj - 1

    if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) { return }
    if ($tumorIndex -eq $script:CurrentIndex) { return }

    Show-Tumor -Index $tumorIndex
})

function Format-Xml {
    param(
        [string]$Xml
    )

    if ([string]::IsNullOrWhiteSpace($Xml)) {
        return $Xml
    }

    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    $doc.LoadXml($Xml)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $doc.Save($xw)
    $xw.Flush()
    $sw.ToString()
}

function Show-RawXmlForTumor {
    param(
        [int]$Index
    )

    if (-not $script:XmlDoc) {
        [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Show XML")
        return
    }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
        [System.Windows.Forms.MessageBox]::Show("Index out of range.", "Show XML")
        return
    }

    $origDoc = $script:XmlDoc
    $root    = $origDoc.DocumentElement
    if (-not $root) {
        [System.Windows.Forms.MessageBox]::Show("Root <NaaccrData> element not found.", "Show XML")
        return
    }

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    if (-not $patient) {
        [System.Windows.Forms.MessageBox]::Show("Patient node for selected tumor not found.", "Show XML")
        return
    }

    # Build a new minimal NAACCR document:
    # - same <NaaccrData> element name/ns and attributes
    # - all non-Patient children (root-level Item nodes, etc.)
    # - only the selected Patient subtree

    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Create NaaccrData root with same name/ns/attributes
    $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
    foreach ($attr in $root.Attributes) {
        $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
        $newAttr.Value = $attr.Value
        [void]$newRoot.Attributes.Append($newAttr)
    }
    [void]$newDoc.AppendChild($newRoot)

    # Copy top-level non-Patient children (e.g. root-level Item nodes)
    foreach ($child in $root.ChildNodes) {
        if ($child.LocalName -eq "Patient") { continue }
        $imported = $newDoc.ImportNode($child, $true)
        [void]$newRoot.AppendChild($imported)
    }

    # Import only the selected Patient subtree
    $importedPatient = $newDoc.ImportNode($patient, $true)
    [void]$newRoot.AppendChild($importedPatient)

    # Serialize new document; reuse original XML declaration if present
    $bodyXml = $newDoc.OuterXml

    $declNode = $origDoc.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlDeclaration] } |
        Select-Object -First 1

    if ($declNode) {
        $finalXml = $declNode.OuterXml + "`r`n" + $bodyXml
    }
    else {
        $finalXml = $bodyXml
    }
	
	$finalXml = Format-Xml -Xml $finalXml

    $label = Get-TumorLabel -Index $Index

    $xmlForm = New-Object System.Windows.Forms.Form
    $xmlForm.Text   = "Raw XML - $label" 
    $xmlForm.Width  = 1400
    $xmlForm.Height = 900
    $xmlForm.StartPosition = "CenterScreen"

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = 'Fill'
    $rtb.ReadOnly = $true
    $rtb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtb.WordWrap = $false
    $rtb.ScrollBars = "Both"

    $rtb.Text = $finalXml

    $xmlForm.Controls.Add($rtb)
    [void]$xmlForm.ShowDialog()
}


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
    Show-RawXmlForTumor -Index $idx
})


# Diff button click
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

    Show-NaaccrTumorDiff -Tumors $script:Tumors -NsMgr $script:NsMgr -IndexA $idxA -IndexB $idxB
})

[void]$form.ShowDialog()
