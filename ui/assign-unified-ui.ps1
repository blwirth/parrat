# assign-unified-ui.ps1
# UI dialogs for unified assignment features

function Show-UnifiedAssignDialog {
    param(
        [string]$FilePath,
        [int]$TumorCount,
        [int]$PatientCount,
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    # Try to extract facility number from filename
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $match = [regex]::Match($fileName, '(?<![0-9])\d{7}(?![0-9])')
    $detectedFacility = if ($match.Success) { $match.Value.PadLeft(10, '0') } else { "" }

    # Scan existing values to show counts and find safe PID starting number
    $maxExistingPid = 0
    $patientsWithPid = 0
    $patientsWithoutPid = 0
    $tumorsWithSite = 0
    $tumorsWithLaterality = 0
    $tumorsWithFacility = 0
    $processedPatients = @{}

    foreach ($tumor in $Tumors) {
        # Count tumor-level fields
        $currentSite = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "primarySite").Trim()
        $currentLat = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "laterality").Trim()
        $currentFac = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "reportingFacility").Trim()

        if (-not [string]::IsNullOrWhiteSpace($currentSite)) { $tumorsWithSite++ }
        if (-not [string]::IsNullOrWhiteSpace($currentLat)) { $tumorsWithLaterality++ }
        if (-not [string]::IsNullOrWhiteSpace($currentFac) -and $currentFac -notmatch '^0+$') { $tumorsWithFacility++ }

        # Count patient-level fields (once per patient)
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)
        if ($null -ne $patient -and -not $processedPatients.ContainsKey($patient)) {
            $processedPatients[$patient] = $true
            $currentPid = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "patientIdNumber"

            if (-not [string]::IsNullOrWhiteSpace($currentPid)) {
                $patientsWithPid++
                # Try to parse as number to find max
                if ($currentPid -match '^\d+$') {
                    $pidNum = [int64]$currentPid
                    if ($pidNum -gt $maxExistingPid) {
                        $maxExistingPid = $pidNum
                    }
                }
            }
            else {
                $patientsWithoutPid++
            }
        }
    }

    $suggestedStartingNumber = $maxExistingPid + 1

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Unified Assignment"
    $form.Width = 500
    $form.Height = 620
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Header info
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(10, 10)
    $lblHeader.Size = New-Object System.Drawing.Size(470, 20)
    $lblHeader.Text = "File: $fileName  |  Tumors: $TumorCount  |  Patients: $PatientCount"
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lblHeader)

    # --- Primary Site & Laterality GroupBox ---
    $grpSiteLat = New-Object System.Windows.Forms.GroupBox
    $grpSiteLat.Text = "Primary Site && Laterality"
    $grpSiteLat.Location = New-Object System.Drawing.Point(10, 40)
    $grpSiteLat.Size = New-Object System.Drawing.Size(465, 140)

    $chkSite = New-Object System.Windows.Forms.CheckBox
    $chkSite.Text = "Assign Primary Site"
    $chkSite.Location = New-Object System.Drawing.Point(15, 25)
    $chkSite.AutoSize = $true
    $chkSite.Checked = $true
    $grpSiteLat.Controls.Add($chkSite)

    $lblSiteStatus = New-Object System.Windows.Forms.Label
    $lblSiteStatus.Text = "$tumorsWithSite of $TumorCount tumors have primary site"
    $lblSiteStatus.Location = New-Object System.Drawing.Point(200, 26)
    $lblSiteStatus.AutoSize = $true
    $lblSiteStatus.ForeColor = [System.Drawing.Color]::Gray
    $grpSiteLat.Controls.Add($lblSiteStatus)

    $chkSiteOverride = New-Object System.Windows.Forms.CheckBox
    $chkSiteOverride.Text = "Override existing values"
    $chkSiteOverride.Location = New-Object System.Drawing.Point(35, 48)
    $chkSiteOverride.AutoSize = $true
    $chkSiteOverride.ForeColor = [System.Drawing.Color]::Red
    $grpSiteLat.Controls.Add($chkSiteOverride)

    $chkLat = New-Object System.Windows.Forms.CheckBox
    $chkLat.Text = "Assign Laterality"
    $chkLat.Location = New-Object System.Drawing.Point(15, 78)
    $chkLat.AutoSize = $true
    $chkLat.Checked = $true
    $grpSiteLat.Controls.Add($chkLat)

    $lblLatStatus = New-Object System.Windows.Forms.Label
    $lblLatStatus.Text = "$tumorsWithLaterality of $TumorCount tumors have laterality"
    $lblLatStatus.Location = New-Object System.Drawing.Point(200, 79)
    $lblLatStatus.AutoSize = $true
    $lblLatStatus.ForeColor = [System.Drawing.Color]::Gray
    $grpSiteLat.Controls.Add($lblLatStatus)

    $chkLatOverride = New-Object System.Windows.Forms.CheckBox
    $chkLatOverride.Text = "Override existing values"
    $chkLatOverride.Location = New-Object System.Drawing.Point(35, 101)
    $chkLatOverride.AutoSize = $true
    $chkLatOverride.ForeColor = [System.Drawing.Color]::Red
    $grpSiteLat.Controls.Add($chkLatOverride)

    $form.Controls.Add($grpSiteLat)

    # --- Facility GroupBox ---
    $grpFacility = New-Object System.Windows.Forms.GroupBox
    $grpFacility.Text = "Facility"
    $grpFacility.Location = New-Object System.Drawing.Point(10, 190)
    $grpFacility.Size = New-Object System.Drawing.Size(465, 100)

    $chkFacility = New-Object System.Windows.Forms.CheckBox
    $chkFacility.Text = "Assign Facility"
    $chkFacility.Location = New-Object System.Drawing.Point(15, 25)
    $chkFacility.AutoSize = $true
    $chkFacility.Checked = $true
    $grpFacility.Controls.Add($chkFacility)

    $lblFacilityStatus = New-Object System.Windows.Forms.Label
    $lblFacilityStatus.Text = "$tumorsWithFacility of $TumorCount tumors have facility"
    $lblFacilityStatus.Location = New-Object System.Drawing.Point(200, 26)
    $lblFacilityStatus.AutoSize = $true
    $lblFacilityStatus.ForeColor = [System.Drawing.Color]::Gray
    $grpFacility.Controls.Add($lblFacilityStatus)

    $lblFacilityNum = New-Object System.Windows.Forms.Label
    $lblFacilityNum.Text = "Number:"
    $lblFacilityNum.Location = New-Object System.Drawing.Point(35, 50)
    $lblFacilityNum.AutoSize = $true
    $grpFacility.Controls.Add($lblFacilityNum)

    $txtFacilityNum = New-Object System.Windows.Forms.TextBox
    $txtFacilityNum.Location = New-Object System.Drawing.Point(95, 47)
    $txtFacilityNum.Width = 120
    $txtFacilityNum.Text = $detectedFacility
    $grpFacility.Controls.Add($txtFacilityNum)

    $lblFacilityDetected = New-Object System.Windows.Forms.Label
    $lblFacilityDetected.Text = if ($detectedFacility) { "(auto-detected)" } else { "(enter manually) (will be padded to 10 digits)" }
    $lblFacilityDetected.Location = New-Object System.Drawing.Point(220, 50)
    $lblFacilityDetected.AutoSize = $true
    $lblFacilityDetected.ForeColor = [System.Drawing.Color]::Gray
    $grpFacility.Controls.Add($lblFacilityDetected)

    $chkFacilityOverride = New-Object System.Windows.Forms.CheckBox
    $chkFacilityOverride.Text = "Override existing values"
    $chkFacilityOverride.Location = New-Object System.Drawing.Point(35, 73)
    $chkFacilityOverride.AutoSize = $true
    $chkFacilityOverride.ForeColor = [System.Drawing.Color]::Red
    $grpFacility.Controls.Add($chkFacilityOverride)

    $form.Controls.Add($grpFacility)

    # --- Patient ID GroupBox ---
    $grpPid = New-Object System.Windows.Forms.GroupBox
    $grpPid.Text = "Patient ID"
    $grpPid.Location = New-Object System.Drawing.Point(10, 300)
    $grpPid.Size = New-Object System.Drawing.Size(465, 170)

    $chkPid = New-Object System.Windows.Forms.CheckBox
    $chkPid.Text = "Assign Patient ID"
    $chkPid.Location = New-Object System.Drawing.Point(15, 25)
    $chkPid.AutoSize = $true
    $chkPid.Checked = $false
    $grpPid.Controls.Add($chkPid)

    # Status label showing current PID situation
    $pidStatusText = "$patientsWithPid of $PatientCount patients have IDs"
    if ($maxExistingPid -gt 0) {
        $pidStatusText += " (highest: $($maxExistingPid.ToString("D8")))"
    }
    $lblPidStatus = New-Object System.Windows.Forms.Label
    $lblPidStatus.Text = $pidStatusText
    $lblPidStatus.Location = New-Object System.Drawing.Point(35, 48)
    $lblPidStatus.Size = New-Object System.Drawing.Size(400, 18)
    $lblPidStatus.ForeColor = [System.Drawing.Color]::Gray
    $grpPid.Controls.Add($lblPidStatus)

    $lblStartingNum = New-Object System.Windows.Forms.Label
    $lblStartingNum.Text = "Start at:"
    $lblStartingNum.Location = New-Object System.Drawing.Point(35, 72)
    $lblStartingNum.AutoSize = $true
    $grpPid.Controls.Add($lblStartingNum)

    $txtStartingNum = New-Object System.Windows.Forms.TextBox
    $txtStartingNum.Location = New-Object System.Drawing.Point(90, 69)
    $txtStartingNum.Width = 100
    $txtStartingNum.Text = $suggestedStartingNumber.ToString("D8")
    $grpPid.Controls.Add($txtStartingNum)

    $lblStartingNumHint = New-Object System.Windows.Forms.Label
    $lblStartingNumHint.Text = "(next available)"
    $lblStartingNumHint.Location = New-Object System.Drawing.Point(195, 72)
    $lblStartingNumHint.AutoSize = $true
    $lblStartingNumHint.ForeColor = [System.Drawing.Color]::Gray
    $grpPid.Controls.Add($lblStartingNumHint)

    $rbPidMissing = New-Object System.Windows.Forms.RadioButton
    $rbPidMissing.Text = "Assign to patients without IDs only"
    $rbPidMissing.Location = New-Object System.Drawing.Point(35, 95)
    $rbPidMissing.AutoSize = $true
    $rbPidMissing.Checked = $true
    $grpPid.Controls.Add($rbPidMissing)

    $rbPidOverwrite = New-Object System.Windows.Forms.RadioButton
    $rbPidOverwrite.Text = "Overwrite all (renumber all patients)"
    $rbPidOverwrite.Location = New-Object System.Drawing.Point(35, 117)
    $rbPidOverwrite.AutoSize = $true
    $rbPidOverwrite.ForeColor = [System.Drawing.Color]::Red
    $grpPid.Controls.Add($rbPidOverwrite)

    $rbPidReplaceZeros = New-Object System.Windows.Forms.RadioButton
    $rbPidReplaceZeros.Text = "Replace zeros only (start at 90000001)"
    $rbPidReplaceZeros.Location = New-Object System.Drawing.Point(35, 139)
    $rbPidReplaceZeros.AutoSize = $true
    $rbPidReplaceZeros.ForeColor = [System.Drawing.Color]::Red
    $grpPid.Controls.Add($rbPidReplaceZeros)

    $form.Controls.Add($grpPid)

    # Enable/disable sub-controls based on parent checkbox
    $updateSiteLatEnabled = {
        $chkSiteOverride.Enabled = $chkSite.Checked
        $chkLatOverride.Enabled = $chkLat.Checked
    }
    $chkSite.Add_CheckedChanged($updateSiteLatEnabled)
    $chkLat.Add_CheckedChanged($updateSiteLatEnabled)

    $updateFacilityEnabled = {
        $txtFacilityNum.Enabled = $chkFacility.Checked
        $chkFacilityOverride.Enabled = $chkFacility.Checked
    }
    $chkFacility.Add_CheckedChanged($updateFacilityEnabled)

    $updatePidEnabled = {
        $rbPidMissing.Enabled = $chkPid.Checked
        $rbPidOverwrite.Enabled = $chkPid.Checked
        $rbPidReplaceZeros.Enabled = $chkPid.Checked

        # Enable starting number for "missing only" and "overwrite all", disable for "replace zeros"
        $txtStartingNum.Enabled = $chkPid.Checked -and -not $rbPidReplaceZeros.Checked

        # Update hint label based on mode
        if ($rbPidReplaceZeros.Checked) {
            $lblStartingNumHint.Text = "(fixed at 90000001)"
        }
        elseif ($rbPidOverwrite.Checked) {
            $lblStartingNumHint.Text = "(renumbers all)"
        }
        else {
            $lblStartingNumHint.Text = "(next available)"
        }
    }
    $chkPid.Add_CheckedChanged($updatePidEnabled)
    $rbPidMissing.Add_CheckedChanged($updatePidEnabled)
    $rbPidOverwrite.Add_CheckedChanged($updatePidEnabled)
    $rbPidReplaceZeros.Add_CheckedChanged($updatePidEnabled)

    # Initialize enabled states
    & $updateSiteLatEnabled
    & $updateFacilityEnabled
    & $updatePidEnabled

    # Buttons
    $btnAnalyze = New-Object System.Windows.Forms.Button
    $btnAnalyze.Text = "Analyze && Preview"
    $btnAnalyze.Width = 130
    $btnAnalyze.Height = 30
    $btnAnalyze.Location = New-Object System.Drawing.Point(250, 540)
    $btnAnalyze.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $btnAnalyze
    $form.Controls.Add($btnAnalyze)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 90
    $btnCancel.Height = 30
    $btnCancel.Location = New-Object System.Drawing.Point(385, 540)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $btnCancel
    $form.Controls.Add($btnCancel)

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Validate facility number if enabled
        if ($chkFacility.Checked) {
            $facNum = $txtFacilityNum.Text.Trim()
            if (-not ($facNum -match '^\d+$')) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Invalid facility number. Must be numeric.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return $null
            }
            # Ensure it's exactly 10 digits (after padding)
            $facNumPadded = $facNum.PadLeft(10, '0')
            if ($facNumPadded.Length -ne 10) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Facility number must be 10 digits or less (will be left-padded with zeros).`nYou entered $($facNum.Length) digits.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return $null
            }
        }

        # Validate starting number if PID enabled with missing-only mode
        if ($chkPid.Checked -and $rbPidMissing.Checked) {
            $startNum = $txtStartingNum.Text.Trim()
            if (-not ($startNum -match '^\d+$')) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Invalid starting number. Must be numeric.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return $null
            }
        }

        # Determine PID mode
        $pidMode = "Default"
        if ($rbPidOverwrite.Checked) { $pidMode = "OverwriteAll" }
        elseif ($rbPidReplaceZeros.Checked) { $pidMode = "ReplaceZeros" }

        return @{
            AssignSite = $chkSite.Checked
            SiteOverride = $chkSiteOverride.Checked
            AssignLaterality = $chkLat.Checked
            LateralityOverride = $chkLatOverride.Checked
            AssignFacility = $chkFacility.Checked
            FacilityNumber = $txtFacilityNum.Text.Trim().PadLeft(10, '0')
            FacilityOverride = $chkFacilityOverride.Checked
            AssignPid = $chkPid.Checked
            PidMode = $pidMode
            PidStartingNumber = [int]$txtStartingNum.Text.Trim()
        }
    }

    return $null
}

function Show-UnifiedPreviewReport {
    param(
        [array]$Report,
        [hashtable]$TumorAssignments,
        [hashtable]$PatientAssignments,
        [hashtable]$Options,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [hashtable]$Controls
    )

    # Count changes
    $siteCount = ($Report | Where-Object { $_.ProposedSite }).Count
    $latCount = ($Report | Where-Object { $_.ProposedLaterality }).Count
    $facCount = ($Report | Where-Object { $_.ProposedFacility }).Count
    $pidCount = ($Report | Where-Object { $_.ProposedPid }).Count
    $totalChanges = ($Report | Where-Object { $_.HasChanges }).Count

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Unified Assignment Preview"
    $reportForm.Width = 1600
    $reportForm.Height = 800
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 30)
    $summaryParts = @("To update: $totalChanges")
    if ($Options.AssignSite) { $summaryParts += "Sites: $siteCount" }
    if ($Options.AssignLaterality) { $summaryParts += "Laterality: $latCount" }
    if ($Options.AssignFacility) { $summaryParts += "Facility: $facCount" }
    if ($Options.AssignPid) { $summaryParts += "Patient IDs: $pidCount" }
    $lblSummary.Text = $summaryParts -join " | "
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # Filter checkbox
    $chkShowChangesOnly = New-Object System.Windows.Forms.CheckBox
    $chkShowChangesOnly.Text = "Show only records with changes"
    $chkShowChangesOnly.Checked = $true
    $chkShowChangesOnly.Location = New-Object System.Drawing.Point(10, 45)
    $chkShowChangesOnly.AutoSize = $true

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

    # Build DataTable with dynamic columns
    $fullTable = New-Object System.Data.DataTable
    [void]$fullTable.Columns.Add("TumorIndex", [int])
    [void]$fullTable.Columns.Add("PatientName", [string])

    if ($Options.AssignSite) {
        [void]$fullTable.Columns.Add("CurrentSite", [string])
        [void]$fullTable.Columns.Add("ProposedSite", [string])
    }
    if ($Options.AssignLaterality) {
        [void]$fullTable.Columns.Add("CurrentLat", [string])
        [void]$fullTable.Columns.Add("ProposedLat", [string])
    }
    if ($Options.AssignFacility) {
        [void]$fullTable.Columns.Add("CurrentFac", [string])
        [void]$fullTable.Columns.Add("ProposedFac", [string])
    }
    if ($Options.AssignPid) {
        [void]$fullTable.Columns.Add("CurrentPid", [string])
        [void]$fullTable.Columns.Add("ProposedPid", [string])
    }
    if ($Options.AssignSite -or $Options.AssignLaterality) {
        [void]$fullTable.Columns.Add("SourceText", [string])
    }
    [void]$fullTable.Columns.Add("HasChanges", [bool])

    foreach ($item in $Report) {
        $row = $fullTable.NewRow()
        $row["TumorIndex"] = $item.TumorIndex
        $row["PatientName"] = $item.PatientName

        if ($Options.AssignSite) {
            $row["CurrentSite"] = $item.CurrentSite
            $row["ProposedSite"] = $item.ProposedSite
        }
        if ($Options.AssignLaterality) {
            $row["CurrentLat"] = $item.CurrentLaterality
            $row["ProposedLat"] = $item.ProposedLaterality
        }
        if ($Options.AssignFacility) {
            $row["CurrentFac"] = $item.CurrentFacility
            $row["ProposedFac"] = $item.ProposedFacility
        }
        if ($Options.AssignPid) {
            $row["CurrentPid"] = $item.CurrentPid
            $row["ProposedPid"] = $item.ProposedPid
        }
        if ($Options.AssignSite -or $Options.AssignLaterality) {
            $row["SourceText"] = $item.SourceText
        }
        $row["HasChanges"] = $item.HasChanges

        [void]$fullTable.Rows.Add($row)
    }

    # Create filtered DataView
    $dataView = New-Object System.Data.DataView($fullTable)
    $grid.DataSource = $dataView

    # Hide HasChanges column
    $hideHasChangesColumn = {
        try {
            if ($null -ne $grid.Columns["HasChanges"]) {
                $grid.Columns["HasChanges"].Visible = $false
            }
        }
        catch { $null = $_.Exception }
    }

    $grid.Add_DataBindingComplete($hideHasChangesColumn)
    $reportForm.Add_Load($hideHasChangesColumn)

    # Filter function
    $updateFilter = {
        if ($chkShowChangesOnly.Checked) {
            $dataView.RowFilter = "HasChanges = True"
        }
        else {
            $dataView.RowFilter = ""
        }
    }

    $chkShowChangesOnly.Add_CheckedChanged($updateFilter)
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
    $btnSaveXml.Text = "Save Updated XML"
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
            $suffix = Get-FileSuffix -Options $Options -Report $Report
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-$suffix.xml")

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
            $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

            Write-UnifiedAssignedXml -XmlDoc $XmlDoc -Tumors $Tumors -TumorAssignments $TumorAssignments -PatientAssignments $PatientAssignments -NsMgr $nsMgr -OutputPath $outputPath

            # Ask user if they want to open the newly created file
            $openResult = [System.Windows.Forms.MessageBox]::Show(
                "Updated XML saved to:`n$outputPath`n`nOpen newly created file?",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($openResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Close the preview form first
                $reportForm.Close()

                # Load the newly created file
                if ($null -ne $Controls) {
                    Import-XmlFile -FilePath $outputPath -Controls $Controls
                }
            }
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
            $suffix = Get-FileSuffix -Options $Options -Report $Report
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-$suffix-report.csv")

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
    $reportForm.Controls.AddRange(@($lblSummary, $chkShowChangesOnly, $splitContainer, $btnSaveXml, $btnSaveCsv, $btnClose))

    [void]$reportForm.ShowDialog()
}
