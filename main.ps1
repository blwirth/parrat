. "$PSScriptRoot\xml-helpers.ps1"
. "$PSScriptRoot\xml-viewer.ps1"
. "$PSScriptRoot\hl7-helpers.ps1"
. "$PSScriptRoot\hl7-viewer.ps1"
. "$PSScriptRoot\diff.ps1"
. "$PSScriptRoot\deduplicate.ps1"
. "$PSScriptRoot\assign-site-laterality.ps1"
. "$PSScriptRoot\assign-facility.ps1"
. "$PSScriptRoot\concatenate-xml.ps1"
. "$PSScriptRoot\concatenate-hl7.ps1"
. "$PSScriptRoot\convert-txt.ps1"
. "$PSScriptRoot\add-pid.ps1"
. "$PSScriptRoot\export-selected-xml.ps1"
. "$PSScriptRoot\export-selected-hl7.ps1"
. "$PSScriptRoot\export-selected-csv.ps1"
. "$PSScriptRoot\export-all-csv.ps1"
. "$PSScriptRoot\export-preview.ps1"
. "$PSScriptRoot\noah-reportability.ps1"

. "$PSScriptRoot\button-handlers\btnOpen.ps1"
. "$PSScriptRoot\button-handlers\btnShowRaw.ps1"
. "$PSScriptRoot\button-handlers\btnDiff.ps1"
. "$PSScriptRoot\button-handlers\btnDedup.ps1"
. "$PSScriptRoot\button-handlers\btnDedupTrueMatches.ps1"
. "$PSScriptRoot\button-handlers\btnDedupPrimaryKey.ps1"
. "$PSScriptRoot\button-handlers\btnDedupPathReport.ps1"
. "$PSScriptRoot\button-handlers\btnAssign.ps1"
. "$PSScriptRoot\button-handlers\btnFacility.ps1"
. "$PSScriptRoot\button-handlers\btnConcatenate.ps1"
. "$PSScriptRoot\button-handlers\btnConvertTxt.ps1"
. "$PSScriptRoot\button-handlers\btnAddPid.ps1"
. "$PSScriptRoot\button-handlers\btnExport.ps1"
. "$PSScriptRoot\button-handlers\btnNoahReportability.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedXml.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedCsv.ps1"
. "$PSScriptRoot\button-handlers\btnExportAllCsv.ps1"
. "$PSScriptRoot\button-handlers\btnPrev.ps1"
. "$PSScriptRoot\button-handlers\btnNext.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form = $form[0]  # ensure scalar type, not array
$form.Text   = "XML and HL7 Utilities"
$form.StartPosition = "CenterScreen"
$form.WindowState   = "Maximized"

# Top nav
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open..."
$btnOpen.Width = 100
$btnOpen.Location = New-Object System.Drawing.Point(10, 10)

$btnDiff = New-Object System.Windows.Forms.Button
$btnDiff.Text = "Diff"
$btnDiff.Width = 100
$btnDiff.Location = New-Object System.Drawing.Point(120, 10)

$btnXml = New-Object System.Windows.Forms.Button
$btnXml.Text = "Show Raw"
$btnXml.Width = 100
$btnXml.Location = New-Object System.Drawing.Point(230, 10)

$btnDedup = New-Object System.Windows.Forms.Button
$btnDedup.Text = "Deduplicate..."
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

$btnAddPid = New-Object System.Windows.Forms.Button
$btnAddPid.Text = "Add PID"
$btnAddPid.Width = 100
$btnAddPid.Location = New-Object System.Drawing.Point(670, 10)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export..."
$btnExport.Width = 100
$btnExport.Location = New-Object System.Drawing.Point(780, 10)

$btnConcatenate = New-Object System.Windows.Forms.Button
$btnConcatenate.Text = "Concatenate..."
$btnConcatenate.Width = 120
$btnConcatenate.Location = New-Object System.Drawing.Point(890, 10)

$btnConvertTxt = New-Object System.Windows.Forms.Button
$btnConvertTxt.Text = "Convert TXT"
$btnConvertTxt.Width = 100
$btnConvertTxt.Location = New-Object System.Drawing.Point(1020, 10)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(1130, 15)
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
$lblIndex.Location = New-Object System.Drawing.Point(110, 985)
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
    param($formSender, $e)

    # Adjust main panel to fit current client area
    $mainPanel.Size = New-Object System.Drawing.Size(
        [int]($formSender.ClientSize.Width  - 20),
        [int]($formSender.ClientSize.Height - 100)  # leave some space at the bottom
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
[void]$table.Columns.Add("Selected", [bool])
[void]$table.Columns.Add("Index", [int])
[void]$table.Columns.Add("nameLast", [string])
[void]$table.Columns.Add("nameFirst", [string])
[void]$table.Columns.Add("dateOfBirth", [string])
[void]$table.Columns.Add("pathReportNumber1", [string])
[void]$table.Columns.Add("primarySite", [string])
[void]$table.Columns.Add("dateOfDiagnosis", [string])

# Bind table BEFORE re-setting selection-related properties
$gridNav.DataSource = $table

# Configure grid: checkbox column editable, others read-only
$gridNav.ReadOnly = $false
$gridNav.MultiSelect = $true
$gridNav.SelectionMode = 'FullRowSelect'
$gridNav.AutoSizeColumnsMode = 'AllCells'

# Note: Column configuration will be done after data is loaded

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
	$btnConcatenate,
	$btnConvertTxt,
    $btnAddPid,
    $btnExport,
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
$script:FileType        = $null    # 'xml' or 'hl7'
$script:Hl7Messages     = @()

# Create hashtables for passing context to button handlers
$script:Controls = @{
    'form' = $form
    'lblStatus' = $lblStatus
    'gridNav' = $gridNav
    'rtbPath' = $rtbPath
    'rtbItems' = $rtbItems
    'btnPrev' = $btnPrev
    'btnNext' = $btnNext
    'lblIndex' = $lblIndex
    'btnExport' = $btnExport
    'btnDedup' = $btnDedup
    'btnConcatenate' = $btnConcatenate
}

$script:ScriptVars = @{
    'Tumors' = $script:Tumors
    'CurrentIndex' = $script:CurrentIndex
    'NsMgr' = $script:NsMgr
    'NavTable' = $script:NavTable
    'XmlDoc' = $script:XmlDoc
    'CurrentFilePath' = $script:CurrentFilePath
    'FileType' = $script:FileType
    'Hl7Messages' = $script:Hl7Messages
}

function Show-Tumor {
    param(
        [int]$Index
    )

    if ($script:Tumors.Count -eq 0) { return }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) { return }

    $script:CurrentIndex = $Index
    $script:ScriptVars['CurrentIndex'] = $Index
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
        if ($null -ne $node) {
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

    if ($null -ne $patient) {
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

$btnOpen.Add_Click((Get-BtnOpenHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

# Grid row selection -> show record based on file type (using Index column, not row position)
$gridNav.Add_SelectionChanged({
    # Determine which data source to use based on file type
    $recordCount = 0
    if ($script:FileType -eq 'hl7') {
        $recordCount = $script:Hl7Messages.Count
    }
    else {
        $recordCount = $script:Tumors.Count
    }
    
    if ($recordCount -eq 0) { return }

    # Only navigate when exactly one row is selected.
    # If user selects multiple rows (Ctrl/Shift), do nothing here.
    if ($gridNav.SelectedRows.Count -ne 1) { return }

    $selectedRow  = $gridNav.SelectedRows[0]
    $indexValObj  = $selectedRow.Cells["Index"].Value
    if ($indexValObj -eq $null) { return }

    $recordIndex = [int]$indexValObj - 1

    if ($recordIndex -lt 0 -or $recordIndex -ge $recordCount) { return }
    if ($recordIndex -eq $script:CurrentIndex) { return }

    # Dispatch to appropriate viewer based on file type
    if ($script:FileType -eq 'hl7') {
        Show-Hl7Message -Index $recordIndex
    }
    else {
        Show-Tumor -Index $recordIndex
    }
})


$btnXml.Add_Click((Get-BtnShowRawHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnDiff.Add_Click((Get-BtnDiffHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnDedup.Add_Click((Get-BtnDedupHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnAssign.Add_Click((Get-BtnAssignHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnFacility.Add_Click((Get-BtnFacilityHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnConcatenate.Add_Click((Get-BtnConcatenateHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnConvertTxt.Add_Click((Get-BtnConvertTxtHandler))
$btnExport.Add_Click((Get-BtnExportHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnAddPid.Add_Click((Get-BtnAddPidHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

$btnPrev.Add_Click((Get-BtnPrevHandler -ScriptVars $script:ScriptVars))
$btnNext.Add_Click((Get-BtnNextHandler -ScriptVars $script:ScriptVars))

[void]$form.ShowDialog()