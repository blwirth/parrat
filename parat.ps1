# Hide the PowerShell console window
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[void][Console.Window]::ShowWindow($consolePtr, 0)  # 0 = SW_HIDE

. "$PSScriptRoot\lib\logging.ps1"
Initialize-ParatLogging

. "$PSScriptRoot\lib\xml-helpers.ps1"
. "$PSScriptRoot\lib\xml-viewer.ps1"
. "$PSScriptRoot\lib\hl7-helpers.ps1"
. "$PSScriptRoot\lib\hl7-viewer.ps1"
. "$PSScriptRoot\lib\diff.ps1"
. "$PSScriptRoot\lib\diff-files.ps1"
. "$PSScriptRoot\lib\deduplicate.ps1"
. "$PSScriptRoot\lib\assign-site-laterality.ps1"
. "$PSScriptRoot\lib\assign-facility.ps1"
. "$PSScriptRoot\lib\assign-unified.ps1"
. "$PSScriptRoot\lib\concatenate-xml.ps1"
. "$PSScriptRoot\lib\concatenate-hl7.ps1"
. "$PSScriptRoot\lib\concatenate-txt.ps1"
. "$PSScriptRoot\lib\convert-txt.ps1"
. "$PSScriptRoot\lib\add-pid.ps1"
. "$PSScriptRoot\lib\fix-obx.ps1"
. "$PSScriptRoot\lib\remove-empty-obx5.ps1"
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
. "$PSScriptRoot\lib\split-file.ps1"
. "$PSScriptRoot\lib\test-site-laterality.ps1"
. "$PSScriptRoot\lib\recent-files.ps1"

. "$PSScriptRoot\button-handlers\btnOpen.ps1"
. "$PSScriptRoot\button-handlers\btnShowRaw.ps1"
. "$PSScriptRoot\button-handlers\btnDiff.ps1"
. "$PSScriptRoot\button-handlers\btnDiffFiles.ps1"
. "$PSScriptRoot\button-handlers\btnDedupTrueMatches.ps1"
. "$PSScriptRoot\button-handlers\btnDedupPrimaryKey.ps1"
. "$PSScriptRoot\button-handlers\btnDedupPathReport.ps1"
. "$PSScriptRoot\button-handlers\btnAssign.ps1"
. "$PSScriptRoot\button-handlers\btnFacility.ps1"
. "$PSScriptRoot\button-handlers\btnAssignUnified.ps1"
. "$PSScriptRoot\button-handlers\btnConvertTxt.ps1"
. "$PSScriptRoot\button-handlers\btnAddPid.ps1"
. "$PSScriptRoot\button-handlers\btnFixObx.ps1"
. "$PSScriptRoot\button-handlers\btnRemoveEmptyObx5.ps1"
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
. "$PSScriptRoot\button-handlers\btnSplit.ps1"
. "$PSScriptRoot\button-handlers\btnManageTables.ps1"
. "$PSScriptRoot\button-handlers\btnTestSiteLaterality.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form = $form[0]  # ensure scalar type, not array
$form.Text   = "PARAT"
$form.StartPosition = "CenterScreen"
$form.WindowState   = "Maximized"

# Menubar (MenuStrip)
$menuStrip = New-Object System.Windows.Forms.MenuStrip
$menuStrip.Dock = 'Top'
$form.MainMenuStrip = $menuStrip

# ---- Menus ----
$mnuFile = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuFile.Text = "File"

$mnuOpen = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuOpen.Text = "Open"
[void]$mnuFile.DropDownItems.Add($mnuOpen)

$mnuOpenRecent = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuOpenRecent.Text = "Open Recent"
[void]$mnuFile.DropDownItems.Add($mnuOpenRecent)

[void]$mnuFile.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuDiffFiles = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuDiffFiles.Text = "Diff Files..."
[void]$mnuFile.DropDownItems.Add($mnuDiffFiles)

[void]$mnuFile.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuConcatenate = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuConcatenate.Text = "Concatenate..."
[void]$mnuFile.DropDownItems.Add($mnuConcatenate)

$mnuSplit = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuSplit.Text = "Split..."
[void]$mnuFile.DropDownItems.Add($mnuSplit)

[void]$mnuFile.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuConvertTxt = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuConvertTxt.Text = "Convert .txt"
[void]$mnuFile.DropDownItems.Add($mnuConvertTxt)

[void]$mnuFile.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuRestart = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuRestart.Text = "Restart Application"
$mnuRestart.Add_Click({
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $MyInvocation.PSCommandPath
    }
    if (-not $scriptPath) {
        $scriptPath = Join-Path $PSScriptRoot "parat.ps1"
    }
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden
    $form.Close()
})
[void]$mnuFile.DropDownItems.Add($mnuRestart)

# File -> Concatenate submenu items
$menuItemConcatenateHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateHl7.Text = "Concatenate HL7"
$menuItemConcatenateHl7.Add_Click({ Start-ConcatenateHl7 })
[void]$mnuConcatenate.DropDownItems.Add($menuItemConcatenateHl7)

$menuItemConcatenateXml = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateXml.Text = "Concatenate XML"
$menuItemConcatenateXml.Add_Click({ Start-ConcatenateXml })
[void]$mnuConcatenate.DropDownItems.Add($menuItemConcatenateXml)

$menuItemConcatenateTxt = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemConcatenateTxt.Text = "Concatenate TXT"
$menuItemConcatenateTxt.Add_Click({ Start-ConcatenateTxt })
[void]$mnuConcatenate.DropDownItems.Add($menuItemConcatenateTxt)

$mnuView = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuView.Text = "View"

$mnuRawRecord = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuRawRecord.Text = "Raw Record"
$mnuRawRecord.Enabled = $false
[void]$mnuView.DropDownItems.Add($mnuRawRecord)

$mnuDiffRecords = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuDiffRecords.Text = "Diff Records"
$mnuDiffRecords.Enabled = $false
[void]$mnuView.DropDownItems.Add($mnuDiffRecords)

$mnuEdit = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuEdit.Text = "Edit"

$mnuAssign = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuAssign.Text = "Assign..."
$mnuAssign.Enabled = $false
[void]$mnuEdit.DropDownItems.Add($mnuAssign)

[void]$mnuEdit.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuModifyHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuModifyHl7.Text = "Modify HL7"
$mnuModifyHl7.Enabled = $false
[void]$mnuEdit.DropDownItems.Add($mnuModifyHl7)

[void]$mnuEdit.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuDeduplicate = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuDeduplicate.Text = "Deduplicate..."
$mnuDeduplicate.Enabled = $false
[void]$mnuEdit.DropDownItems.Add($mnuDeduplicate)

# Edit -> Deduplicate submenu items
$menuItemTrueMatches = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemTrueMatches.Text = "Dedup true matches"
[void]$mnuDeduplicate.DropDownItems.Add($menuItemTrueMatches)

$menuItemPathReport = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemPathReport.Text = "Dedup by pathReportNumber1"
[void]$mnuDeduplicate.DropDownItems.Add($menuItemPathReport)

$menuItemPrimaryKey = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemPrimaryKey.Text = "Dedup by primary key"
[void]$mnuDeduplicate.DropDownItems.Add($menuItemPrimaryKey)

$mnuExport = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuExport.Text = "Export"
$mnuExport.Enabled = $false

# Tools menu (replaces NOAH menu)
$mnuTools = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuTools.Text = "Tools"

$mnuTestSiteLatCurrent = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuTestSiteLatCurrent.Text = "Test current record (Site/Lat)"
$mnuTestSiteLatCurrent.Enabled = $false

$mnuTestSiteLatCustom = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuTestSiteLatCustom.Text = "Test custom text (Site/Lat)"

$mnuFilterCurrentHl7 = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuFilterCurrentHl7.Text = "Filter current HL7 (NOAH)"
$mnuFilterCurrentHl7.Enabled = $false

$mnuFilterCustomPayload = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuFilterCustomPayload.Text = "Filter custom payload (NOAH)"

# Build Tools menu items
[void]$mnuTools.DropDownItems.Add($mnuTestSiteLatCurrent)
[void]$mnuTools.DropDownItems.Add($mnuTestSiteLatCustom)
[void]$mnuTools.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$mnuTools.DropDownItems.Add($mnuFilterCurrentHl7)
[void]$mnuTools.DropDownItems.Add($mnuFilterCustomPayload)

$mnuSettings = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuSettings.Text = "Settings"

$mnuManageCodingTables = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuManageCodingTables.Text = "Manage Coding Tables"
[void]$mnuSettings.DropDownItems.Add($mnuManageCodingTables)

$mnuNoahConfig = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuNoahConfig.Text = "NOAH Configuration"
[void]$mnuSettings.DropDownItems.Add($mnuNoahConfig)

$mnuHelp = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuHelp.Text = "Help"

$mnuUserManual = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuUserManual.Text = "User Manual"
$mnuUserManual.Add_Click({ })  # no-op for now
[void]$mnuHelp.DropDownItems.Add($mnuUserManual)

[void]$mnuHelp.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$mnuOpenLogs = New-Object System.Windows.Forms.ToolStripMenuItem
$mnuOpenLogs.Text = "Open Logs Folder"
$mnuOpenLogs.Add_Click({
    $logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Start-Process "explorer.exe" -ArgumentList "`"$logDir`""
})
[void]$mnuHelp.DropDownItems.Add($mnuOpenLogs)

[void]$menuStrip.Items.AddRange(@(
    $mnuFile,
    $mnuView,
    $mnuEdit,
    $mnuExport,
    $mnuTools,
    $mnuSettings,
    $mnuHelp
))

# Status bar (StatusStrip)
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.Dock = 'Bottom'

$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.Text = "No file loaded"
$lblStatus.Spring = $true
[void]$statusStrip.Items.Add($lblStatus)

$lblFileName = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblFileName.Text = ""
$lblFileName.BorderSides = 'Left'
[void]$statusStrip.Items.Add($lblFileName)

# --- Main resizable area (panel + split containers) ---

# Panel to host the split containers, leaving room for ToolStrip and bottom nav
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = 'Fill'
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 10)

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

$bottomPanel.Controls.AddRange(@($btnPrev, $btnNext, $lblIndex))

# Add everything to the form
$form.Controls.AddRange(@(
    $mainPanel,
$bottomPanel,
    $statusStrip,
    $menuStrip
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
    'mnuOpen' = $mnuOpen
    'mnuOpenRecent' = $mnuOpenRecent
    'mnuDiffFiles' = $mnuDiffFiles
    'mnuConcatenate' = $mnuConcatenate
    'mnuSplit' = $mnuSplit
    'mnuConvertTxt' = $mnuConvertTxt
    'mnuRawRecord' = $mnuRawRecord
    'mnuDiffRecords' = $mnuDiffRecords
    'mnuAssign' = $mnuAssign
    'mnuModifyHl7' = $mnuModifyHl7
    'mnuDeduplicate' = $mnuDeduplicate
    'mnuExport' = $mnuExport
    'mnuTools' = $mnuTools
    'mnuTestSiteLatCurrent' = $mnuTestSiteLatCurrent
    'mnuTestSiteLatCustom' = $mnuTestSiteLatCustom
    'mnuFilterCurrentHl7' = $mnuFilterCurrentHl7
    'mnuFilterCustomPayload' = $mnuFilterCustomPayload
    'mnuManageCodingTables' = $mnuManageCodingTables
    'mnuNoahConfig' = $mnuNoahConfig
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
    
    # Enable menu items that require a file (any file type)
    $hasFile = ($null -ne $FileType -and $FileType -ne '')
    
    if ($Controls['mnuRawRecord'])    { $Controls['mnuRawRecord'].Enabled = $hasFile }
    if ($Controls['mnuDiffRecords'])  { $Controls['mnuDiffRecords'].Enabled = $hasFile }
    if ($Controls['mnuDeduplicate'])  { $Controls['mnuDeduplicate'].Enabled = $hasFile }
    if ($Controls['mnuExport'])       { $Controls['mnuExport'].Enabled = $hasFile }
    
    # XML-specific buttons should be enabled only for XML files
    $isXmlFile = ($FileType -eq 'xml')
    
    if ($Controls['mnuAssign']) { $Controls['mnuAssign'].Enabled = $isXmlFile }
    
    # HL7-specific buttons should be enabled only for HL7 files
    $isHl7File = ($FileType -eq 'hl7')
    
    if ($Controls['mnuModifyHl7']) { $Controls['mnuModifyHl7'].Enabled = $isHl7File }
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

    $selectedCount = @($table.Rows | Where-Object { $_["Selected"] -eq $true }).Count
    $lblIndex.Text = "Tumor {0} of {1} ({2} selected)" -f ($Index + 1), $script:Tumors.Count, $selectedCount
    $btnPrev.Enabled = ($Index -gt 0)
    $btnNext.Enabled = ($Index -lt ($script:Tumors.Count - 1))
    
    # Clear re-entry guard
    $script:IsShowingTumor = $false
}

$mnuOpen.Add_Click((Get-BtnOpenHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

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

# Commit checkbox changes immediately when clicked
$gridNav.Add_CurrentCellDirtyStateChanged({
    if ($gridNav.IsCurrentCellDirty -and $gridNav.CurrentCell.ColumnIndex -eq 0) {
        $gridNav.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

# Update selected count when checkbox is toggled
$gridNav.Add_CellValueChanged({
    param($sender, $e)

    # Only handle changes to the "Selected" column (column 0)
    if ($e.ColumnIndex -ne 0) { return }
    if ($global:IsLoadingData -eq $true -or $script:IsLoadingData -eq $true) { return }

    $dataTable = $gridNav.DataSource
    if ($null -eq $dataTable) { return }

    $selectedCount = @($dataTable.Rows | Where-Object { $_["Selected"] -eq $true }).Count
    $fileType = $global:FileType
    if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }

    if ($fileType -eq 'hl7') {
        $messages = $global:Hl7Messages
        if ($null -eq $messages) { $messages = $script:Hl7Messages }
        $totalCount = if ($null -ne $messages) { $messages.Count } else { 0 }
        $currentIdx = $global:CurrentIndex
        if ($null -eq $currentIdx) { $currentIdx = $script:CurrentIndex }
        $lblIndex.Text = "Message {0} of {1} ({2} selected)" -f ($currentIdx + 1), $totalCount, $selectedCount
    }
    else {
        $lblIndex.Text = "Tumor {0} of {1} ({2} selected)" -f ($script:CurrentIndex + 1), $script:Tumors.Count, $selectedCount
    }
})

# Wire up button handlers
$mnuRawRecord.Add_Click((Get-BtnShowRawHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$mnuDiffRecords.Add_Click((Get-BtnDiffHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$mnuDiffFiles.Add_Click((Get-BtnDiffFilesHandler))
$mnuConvertTxt.Add_Click((Get-BtnConvertTxtHandler))

# Wire up unified Assign handler (replaces previous submenu)
$mnuAssign.Add_Click((Get-BtnAssignUnifiedHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

# Set up Modify HL7 dropdown menu
$menuItemFixObx31 = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemFixObx31.Text = "Fix OBX 3.1"
$menuItemFixObx31.Add_Click((Get-BtnFixObx3Handler -Controls $script:Controls -ScriptVars $script:ScriptVars))
[void]$mnuModifyHl7.DropDownItems.Add($menuItemFixObx31)

$menuItemRemoveEmptyObx5 = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemRemoveEmptyObx5.Text = "Remove Empty OBX 5"
$menuItemRemoveEmptyObx5.Add_Click((Get-BtnRemoveEmptyObx5Handler -Controls $script:Controls -ScriptVars $script:ScriptVars))
[void]$mnuModifyHl7.DropDownItems.Add($menuItemRemoveEmptyObx5)
# Wire up Tools menu handlers
$mnuTestSiteLatCurrent.Add_Click((Get-BtnTestSiteLatCurrentHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$mnuTestSiteLatCustom.Add_Click((Get-BtnTestSiteLatCustomHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

$mnuFilterCurrentHl7.Add_Click({
    Invoke-PostSelectedHL7 -Controls $script:Controls -ScriptVars $script:ScriptVars
})

$mnuFilterCustomPayload.Add_Click({
    Invoke-PostCustomPayload -Controls $script:Controls -ScriptVars $script:ScriptVars
})

# Wire up NOAH Configuration in Settings menu
$mnuNoahConfig.Add_Click({
    Invoke-NoahSettings -Controls $script:Controls -ScriptVars $script:ScriptVars
})

# Enable menu items dynamically when Tools menu opens
$mnuTools.Add_DropDownOpening({
    $fileType = $global:FileType
    if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }
    $mnuFilterCurrentHl7.Enabled = ($fileType -eq 'hl7')
    $mnuTestSiteLatCurrent.Enabled = ($fileType -eq 'xml')
})

# Populate Open Recent submenu dynamically when opened
$mnuOpenRecent.Add_DropDownOpening({
    param($sender, $e)

    # Clear existing items
    $sender.DropDownItems.Clear()

    $recentFiles = Get-RecentFiles

    if ($recentFiles.Count -eq 0) {
        $emptyItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $emptyItem.Text = "(No recent files)"
        $emptyItem.Enabled = $false
        [void]$sender.DropDownItems.Add($emptyItem)
    }
    else {
        foreach ($file in $recentFiles) {
            $menuItem = New-Object System.Windows.Forms.ToolStripMenuItem
            $filePath = $file.path
            $fileType = $file.fileType

            if (Test-Path $filePath) {
                $menuItem.Text = $filePath
                $menuItem.Tag = @{ Path = $filePath; FileType = $fileType }
                $menuItem.Add_Click({
                    param($clickSender, $clickArgs)
                    $info = $clickSender.Tag
                    if ($info.FileType -eq 'hl7') {
                        Load-Hl7File -FilePath $info.Path -Controls $script:Controls -ScriptVars $script:ScriptVars
                    }
                    else {
                        Load-XmlFile -FilePath $info.Path -Controls $script:Controls -ScriptVars $script:ScriptVars
                    }
                })
            }
            else {
                $menuItem.Text = "$filePath (not found)"
                $menuItem.Enabled = $false
            }

            [void]$sender.DropDownItems.Add($menuItem)
        }
    }

    # Add separator and Clear option
    [void]$sender.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $clearItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $clearItem.Text = "Clear Recent Files"
    $clearItem.Add_Click({
        Clear-RecentFiles
    })
    [void]$sender.DropDownItems.Add($clearItem)
})

# Wire up Deduplicate submenu item handlers
$menuItemTrueMatches.Add_Click((Get-BtnDedupTrueMatchesHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$menuItemPathReport.Add_Click((Get-BtnDedupPathReportHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))
$menuItemPrimaryKey.Add_Click((Get-BtnDedupPrimaryKeyHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

# Set up Export dropdown menu (populated dynamically on DropDownOpening)
$mnuExport.Add_DropDownOpening({
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

# Set up Manage Coding Tables dropdown menu (populated dynamically on DropDownOpening)
$mnuManageCodingTables.Add_DropDownOpening((Get-BtnManageTablesHandler -Controls $script:Controls -ScriptVars $script:ScriptVars))

# Wire up Split button
$mnuSplit.Add_Click((Get-BtnSplitHandler))

$btnPrev.Add_Click((Get-BtnPrevHandler -ScriptVars $script:ScriptVars))
$btnNext.Add_Click((Get-BtnNextHandler -ScriptVars $script:ScriptVars))

# Close logging on form close
$form.Add_FormClosing({
    Close-ParatLogging
})

[void]$form.ShowDialog()