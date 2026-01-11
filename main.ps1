. "$PSScriptRoot\lib\xml-helpers.ps1"
. "$PSScriptRoot\lib\xml-viewer.ps1"
. "$PSScriptRoot\lib\hl7-helpers.ps1"
. "$PSScriptRoot\lib\hl7-viewer.ps1"
. "$PSScriptRoot\lib\diff.ps1"
. "$PSScriptRoot\lib\deduplicate.ps1"
. "$PSScriptRoot\lib\assign-site-laterality.ps1"
. "$PSScriptRoot\lib\assign-facility.ps1"
. "$PSScriptRoot\lib\concatenate-xml.ps1"
. "$PSScriptRoot\lib\concatenate-hl7.ps1"
. "$PSScriptRoot\lib\concatenate-txt.ps1"
. "$PSScriptRoot\lib\convert-txt.ps1"
. "$PSScriptRoot\lib\add-pid.ps1"
. "$PSScriptRoot\lib\fix-obx.ps1"
. "$PSScriptRoot\lib\naaccr-dictionary.ps1"
. "$PSScriptRoot\lib\export-config.ps1"
. "$PSScriptRoot\lib\export-selected-xml.ps1"
. "$PSScriptRoot\lib\export-selected-hl7.ps1"
. "$PSScriptRoot\lib\export-selected-csv.ps1"
. "$PSScriptRoot\lib\export-all-csv.ps1"
. "$PSScriptRoot\lib\export-selected-hl7-csv.ps1"
. "$PSScriptRoot\lib\export-all-hl7-csv.ps1"
. "$PSScriptRoot\lib\export-preview.ps1"
. "$PSScriptRoot\lib\noah-reportability.ps1"
. "$PSScriptRoot\lib\noah-results-viewer.ps1"

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
. "$PSScriptRoot\button-handlers\btnFixObx.ps1"
. "$PSScriptRoot\button-handlers\btnExport.ps1"
. "$PSScriptRoot\button-handlers\btnNoahReportability.ps1"
. "$PSScriptRoot\button-handlers\btnNoahMenu.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedXml.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedCsv.ps1"
. "$PSScriptRoot\button-handlers\btnExportAllCsv.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedHl7.ps1"
. "$PSScriptRoot\button-handlers\btnExportSelectedHl7Csv.ps1"
. "$PSScriptRoot\button-handlers\btnExportAllHl7Csv.ps1"
. "$PSScriptRoot\button-handlers\btnPrev.ps1"
. "$PSScriptRoot\button-handlers\btnNext.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form = $form[0]  # ensure scalar type, not array
$form.Text   = "NAACCR XML and HL7 Utilities"
$form.StartPosition = "CenterScreen"
$form.WindowState   = "Maximized"

# Top nav - ToolStrip
$toolStrip = New-Object System.Windows.Forms.ToolStrip
$toolStrip.Dock = 'Top'

# File operations
$btnOpen = New-Object System.Windows.Forms.ToolStripButton
$btnOpen.Text = "Open..."
$btnOpen.DisplayStyle = 'Text'
[void]$toolStrip.Items.Add($btnOpen)

$btnXml = New-Object System.Windows.Forms.ToolStripButton
$btnXml.Text = "Show Raw"
$btnXml.DisplayStyle = 'Text'
$btnXml.Enabled = $false  # Disabled until file is loaded
[void]$toolStrip.Items.Add($btnXml)

[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Processing operations
$btnDiff = New-Object System.Windows.Forms.ToolStripButton
$btnDiff.Text = "Diff"
$btnDiff.DisplayStyle = 'Text'
$btnDiff.Enabled = $false  # Disabled until file is loaded
[void]$toolStrip.Items.Add($btnDiff)

$btnDedup = New-Object System.Windows.Forms.ToolStripDropDownButton
$btnDedup.Text = "Deduplicate..."
$btnDedup.DisplayStyle = 'Text'
$btnDedup.Enabled = $false  # Disabled until file is loaded
[void]$toolStrip.Items.Add($btnDedup)

$btnAssign = New-Object System.Windows.Forms.ToolStripButton
$btnAssign.Text = "Assign Site/Lat"
$btnAssign.DisplayStyle = 'Text'
$btnAssign.Enabled = $false  # Disabled until file is loaded (XML-specific)
[void]$toolStrip.Items.Add($btnAssign)

$btnFacility = New-Object System.Windows.Forms.ToolStripButton
$btnFacility.Text = "Assign Facility"
$btnFacility.DisplayStyle = 'Text'
$btnFacility.Enabled = $false  # Disabled until file is loaded (XML-specific)
[void]$toolStrip.Items.Add($btnFacility)

$btnAddPid = New-Object System.Windows.Forms.ToolStripButton
$btnAddPid.Text = "Add PID"
$btnAddPid.DisplayStyle = 'Text'
$btnAddPid.Enabled = $false  # Disabled until file is loaded (XML-specific)
[void]$toolStrip.Items.Add($btnAddPid)

$btnFixObx = New-Object System.Windows.Forms.ToolStripButton
$btnFixObx.Text = "Fix OBX"
$btnFixObx.DisplayStyle = 'Text'
$btnFixObx.Enabled = $false  # Disabled until file is loaded (HL7-specific)
[void]$toolStrip.Items.Add($btnFixObx)

[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Export/Convert operations
$btnExport = New-Object System.Windows.Forms.ToolStripDropDownButton
$btnExport.Text = "Export..."
$btnExport.DisplayStyle = 'Text'
$btnExport.Enabled = $false  # Disabled until file is loaded
[void]$toolStrip.Items.Add($btnExport)

[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$btnConcatenate = New-Object System.Windows.Forms.ToolStripDropDownButton
$btnConcatenate.Text = "Concatenate..."
$btnConcatenate.DisplayStyle = 'Text'
# Concatenate stays enabled - doesn't require a file
[void]$toolStrip.Items.Add($btnConcatenate)

$btnConvertTxt = New-Object System.Windows.Forms.ToolStripButton
$btnConvertTxt.Text = "Convert TXT"
$btnConvertTxt.DisplayStyle = 'Text'
# Convert TXT stays enabled - doesn't require a file
[void]$toolStrip.Items.Add($btnConvertTxt)

$btnNoahMenu = New-Object System.Windows.Forms.ToolStripDropDownButton
$btnNoahMenu.Text = "NOAH..."
$btnNoahMenu.DisplayStyle = 'Text'
# NOAH stays enabled - doesn't require a file
[void]$toolStrip.Items.Add($btnNoahMenu)

[void]$toolStrip.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Status label
$lblStatus = New-Object System.Windows.Forms.ToolStripLabel
$lblStatus.Text = "No file loaded"
$lblStatus.Alignment = 'Right'
[void]$toolStrip.Items.Add($lblStatus)

# --- Main resizable area (panel + split containers) ---

# Panel to host the split containers, leaving room for ToolStrip and bottom nav
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = 'Fill'
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(10, 25, 10, 10)

# Outer split container: left (grid) | right (inner split: path + items)
$splitOuter = New-Object System.Windows.Forms.SplitContainer
$splitOuter.Dock = 'Fill'
$splitOuter.Orientation = 'Vertical'
$splitOuter.IsSplitterFixed = $false
$splitOuter.Panel1MinSize = 200
# Panel2MinSize set in Shown event after form has dimensions

# Inner split container: middle (path text) | right (other items)
$splitInner = New-Object System.Windows.Forms.SplitContainer
$splitInner.Dock = 'Fill'
$splitInner.Orientation = 'Vertical'
$splitInner.IsSplitterFixed = $false
$splitInner.Panel1MinSize = 200
# Panel2MinSize set in Shown event after form has dimensions

$form.Add_Shown({
    param($formSender, $e)

    # Set min sizes and splitter distances after form has proper dimensions
    $splitOuter.Panel2MinSize = 400
    $splitInner.Panel2MinSize = 200
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

# Bottom nav panel
$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Dock = 'Bottom'
$bottomPanel.Height = 50
$bottomPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "<"
$btnPrev.Width = 40
$btnPrev.Height = 30
$btnPrev.Location = New-Object System.Drawing.Point(10, 10)
$btnPrev.Enabled = $false
$btnPrev.Anchor = 'Left,Bottom'

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = ">"
$btnNext.Width = 40
$btnNext.Height = 30
$btnNext.Location = New-Object System.Drawing.Point(60, 10)
$btnNext.Enabled = $false
$btnNext.Anchor = 'Left,Bottom'

$lblIndex = New-Object System.Windows.Forms.Label
$lblIndex.AutoSize = $true
$lblIndex.Location = New-Object System.Drawing.Point(110, 15)
$lblIndex.Text = ""
$lblIndex.Anchor = 'Left,Bottom'

$lblFileName = New-Object System.Windows.Forms.Label
$lblFileName.AutoSize = $true
$lblFileName.Location = New-Object System.Drawing.Point(200, 15)
$lblFileName.Text = ""
$lblFileName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFileName.Anchor = 'Left,Bottom'

$bottomPanel.Controls.AddRange(@($btnPrev, $btnNext, $lblIndex, $lblFileName))

# Add everything to the form
$form.Controls.AddRange(@(
    $toolStrip,
    $mainPanel,
    $bottomPanel
))

# State (script scope)
$script:Tumors          = @()
$script:CurrentIndex    = -1
$script:NsMgr           = $null
$script:NavTable        = $null
$script:XmlDoc          = $null
$script:CurrentFilePath = $null
$script:FileType        = $null    # 'xml' or 'hl7'
$script:Hl7Messages     = @()
$script:IsLoadingData   = $false   # Flag to prevent event recursion during data loading
$script:IsShowingTumor  = $false   # Flag to prevent Show-Tumor re-entry

# Global state (for cross-file access)
$global:Hl7Messages     = @()
$global:CurrentIndex    = -1
$global:FileType        = $null
$global:IsLoadingData   = $false

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
    'lblFileName' = $lblFileName
    'btnXml' = $btnXml
    'btnDiff' = $btnDiff
    'btnExport' = $btnExport
    'btnDedup' = $btnDedup
    'btnConcatenate' = $btnConcatenate
    'btnAssign' = $btnAssign
    'btnFacility' = $btnFacility
    'btnAddPid' = $btnAddPid
    'btnFixObx' = $btnFixObx
    'btnNoahMenu' = $btnNoahMenu
}

# Global controls reference for cross-file access
$global:AppControls = $script:Controls

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

function Update-ButtonStatesForFileType {
    param(
        [hashtable]$Controls,
        [string]$FileType
    )
    
    # Enable buttons that require a file (any file type)
    $hasFile = ($null -ne $FileType -and $FileType -ne '')
    
    if ($Controls['btnXml']) {
        $Controls['btnXml'].Enabled = $hasFile
    }
    if ($Controls['btnDiff']) {
        $Controls['btnDiff'].Enabled = $hasFile
    }
    if ($Controls['btnDedup']) {
        $Controls['btnDedup'].Enabled = $hasFile
    }
    if ($Controls['btnExport']) {
        $Controls['btnExport'].Enabled = $hasFile
    }
    
    # XML-specific buttons should be enabled only for XML files
    $isXmlFile = ($FileType -eq 'xml')
    
    if ($Controls['btnAssign']) {
        $Controls['btnAssign'].Enabled = $isXmlFile
    }
    if ($Controls['btnFacility']) {
        $Controls['btnFacility'].Enabled = $isXmlFile
    }
    if ($Controls['btnAddPid']) {
        $Controls['btnAddPid'].Enabled = $isXmlFile
    }
    
    # HL7-specific buttons should be enabled only for HL7 files
    $isHl7File = ($FileType -eq 'hl7')
    
    if ($Controls['btnFixObx']) {
        $Controls['btnFixObx'].Enabled = $isHl7File
    }
}

function Show-Tumor {
    param(
        [int]$Index
    )

    if ($script:Tumors.Count -eq 0) { return }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) { return }
    
    # Prevent re-entry (recursion guard)
    if ($script:IsShowingTumor -eq $true) { return }
    $script:IsShowingTumor = $true

    $script:CurrentIndex = $Index
    $script:ScriptVars['CurrentIndex'] = $Index
    $global:CurrentIndex = $Index
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
    
    # Clear re-entry guard
    $script:IsShowingTumor = $false
}

$btnOpen.Add_Click((Get-BtnOpenHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

# Grid row selection -> show record based on file type (using Index column, not row position)
$gridNav.Add_SelectionChanged({
    # Skip event handling during data loading or when Show-Tumor is running to prevent recursion
    if ($global:IsLoadingData -eq $true -or $script:IsLoadingData -eq $true) { return }
    if ($script:IsShowingTumor -eq $true) { return }
    
    # Determine which data source to use based on file type
    $recordCount = 0
    # Use global variables for cross-file access
    $fileType = $global:FileType
    if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }
    
    if ($fileType -eq 'hl7') {
        $messages = $global:Hl7Messages
        if ($null -eq $messages) { $messages = $script:Hl7Messages }
        $recordCount = if ($null -ne $messages) { $messages.Count } else { 0 }
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
    
    $currentIdx = $global:CurrentIndex
    if ($null -eq $currentIdx) { $currentIdx = $script:CurrentIndex }
    if ($recordIndex -eq $currentIdx) { return }

    # Dispatch to appropriate viewer based on file type
    if ($fileType -eq 'hl7') {
        Show-Hl7Message -Index $recordIndex -Messages $global:Hl7Messages -Controls $script:Controls
    }
    else {
        Show-Tumor -Index $recordIndex
    }
})


# Wire up button handlers
$btnXml.Add_Click((Get-BtnShowRawHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnDiff.Add_Click((Get-BtnDiffHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnAssign.Add_Click((Get-BtnAssignHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnFacility.Add_Click((Get-BtnFacilityHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnConvertTxt.Add_Click((Get-BtnConvertTxtHandler))
$btnAddPid.Add_Click((Get-BtnAddPidHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$btnFixObx.Add_Click((Get-BtnFixObxHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
# Set up NOAH dropdown menu (populated dynamically on DropDownOpening)
$btnNoahMenu.Add_DropDownOpening({
    param($toolStripButton, $e)
    
    # Clear existing items
    $toolStripButton.DropDownItems.Clear()
    
    # Determine file type
    $fileType = $global:FileType
    if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }
    $isHl7 = ($fileType -eq 'hl7')
    
    # POST current HL7 (HL7 output) - only enabled if HL7 file is loaded
    $menuItemPostCurrentHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemPostCurrentHl7.Text = "POST current HL7 (HL7 output)"
    $menuItemPostCurrentHl7.Enabled = $isHl7
    $menuItemPostCurrentHl7.Add_Click({
        Invoke-PostSelectedHL7 -Controls $script:Controls -ScriptVars $script:ScriptVars -OutputFormat "hl7"
    })
    [void]$toolStripButton.DropDownItems.Add($menuItemPostCurrentHl7)
    
    # POST current HL7 (XML output) - only enabled if HL7 file is loaded
    $menuItemPostCurrentXml = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemPostCurrentXml.Text = "POST current HL7 (XML output)"
    $menuItemPostCurrentXml.Enabled = $isHl7
    $menuItemPostCurrentXml.Add_Click({
        Invoke-PostSelectedHL7 -Controls $script:Controls -ScriptVars $script:ScriptVars -OutputFormat "xml"
    })
    [void]$toolStripButton.DropDownItems.Add($menuItemPostCurrentXml)
    
    # Separator
    [void]$toolStripButton.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    
    # POST custom payload (HL7 output) - always enabled
    $menuItemCustomHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemCustomHl7.Text = "POST custom payload (HL7 output)"
    $menuItemCustomHl7.Add_Click({
        Invoke-PostCustomPayload -Controls $script:Controls -ScriptVars $script:ScriptVars -OutputFormat "hl7"
    })
    [void]$toolStripButton.DropDownItems.Add($menuItemCustomHl7)
    
    # POST custom payload (XML output) - always enabled
    $menuItemCustomXml = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemCustomXml.Text = "POST custom payload (XML output)"
    $menuItemCustomXml.Add_Click({
        Invoke-PostCustomPayload -Controls $script:Controls -ScriptVars $script:ScriptVars -OutputFormat "xml"
    })
    [void]$toolStripButton.DropDownItems.Add($menuItemCustomXml)
})

# Set up Dedup dropdown menu
$menuItemTrueMatches = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemTrueMatches.Text = "Dedup true matches"
$menuItemTrueMatches.Add_Click((Get-BtnDedupTrueMatchesHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
[void]$btnDedup.DropDownItems.Add($menuItemTrueMatches)

$menuItemPathReport = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemPathReport.Text = "Dedup by pathReportNumber1"
$menuItemPathReport.Add_Click((Get-BtnDedupPathReportHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
[void]$btnDedup.DropDownItems.Add($menuItemPathReport)

$menuItemPrimaryKey = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemPrimaryKey.Text = "Dedup by primary key"
$menuItemPrimaryKey.Add_Click((Get-BtnDedupPrimaryKeyHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
[void]$btnDedup.DropDownItems.Add($menuItemPrimaryKey)

# Set up Export dropdown menu (populated dynamically on DropDownOpening)
$btnExport.Add_DropDownOpening({
    param($toolStripButton, $e)
    
    # Clear existing items
    $toolStripButton.DropDownItems.Clear()
    
    # Determine file type
    $fileType = $script:FileType
    $isXml = ($fileType -eq 'xml')
    $isHl7 = ($fileType -eq 'hl7')
    
    # Export Selected as XML (XML only)
    $menuItemXml = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemXml.Text = "Export Selected as XML"
    $menuItemXml.Enabled = $isXml
    $menuItemXml.Add_Click((Get-BtnExportSelectedXmlHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    [void]$toolStripButton.DropDownItems.Add($menuItemXml)
    
    # Export Selected as HL7 (HL7 only)
    $menuItemHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemHl7.Text = "Export Selected as HL7"
    $menuItemHl7.Enabled = $isHl7
    $menuItemHl7.Add_Click((Get-BtnExportSelectedHl7Handler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    [void]$toolStripButton.DropDownItems.Add($menuItemHl7)
    
    [void]$toolStripButton.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    
    # Export All as CSV (context-aware)
    $menuItemAllCsv = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemAllCsv.Text = "Export All as CSV"
    $menuItemAllCsv.Enabled = ($isXml -or $isHl7)
    if ($isXml) {
        $menuItemAllCsv.Add_Click((Get-BtnExportAllCsvHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    } elseif ($isHl7) {
        $menuItemAllCsv.Add_Click((Get-BtnExportAllHl7CsvHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    }
    [void]$toolStripButton.DropDownItems.Add($menuItemAllCsv)
    
    # Export Selected as CSV (context-aware)
    $menuItemSelectedCsv = New-Object System.Windows.Forms.ToolStripMenuItem
    $menuItemSelectedCsv.Text = "Export Selected as CSV"
    $menuItemSelectedCsv.Enabled = ($isXml -or $isHl7)
    if ($isXml) {
        $menuItemSelectedCsv.Add_Click((Get-BtnExportSelectedCsvHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    } elseif ($isHl7) {
        $menuItemSelectedCsv.Add_Click((Get-BtnExportSelectedHl7CsvHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
    }
    [void]$toolStripButton.DropDownItems.Add($menuItemSelectedCsv)
})

# Set up Concatenate dropdown menu
$menuItemConcatenateHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateHl7.Text = "Concatenate HL7"
$menuItemConcatenateHl7.Add_Click({
    Start-ConcatenateHl7
})
[void]$btnConcatenate.DropDownItems.Add($menuItemConcatenateHl7)

$menuItemConcatenateXml = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateXml.Text = "Concatenate XML"
$menuItemConcatenateXml.Add_Click({
    Start-ConcatenateXml
})
[void]$btnConcatenate.DropDownItems.Add($menuItemConcatenateXml)

$menuItemConcatenateTxt = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateTxt.Text = "Concatenate TXT"
$menuItemConcatenateTxt.Add_Click({
    Start-ConcatenateTxt
})
[void]$btnConcatenate.DropDownItems.Add($menuItemConcatenateTxt)

$btnPrev.Add_Click((Get-BtnPrevHandler -ScriptVars $script:ScriptVars))
$btnNext.Add_Click((Get-BtnNextHandler -ScriptVars $script:ScriptVars))

[void]$form.ShowDialog()