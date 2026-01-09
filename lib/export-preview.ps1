# export-preview.ps1
# Preview function for CSV exports with integrated field selector

function Show-ExportPreview {
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [array]$FieldList,
        [string]$Title = "Export Preview"
    )

    if ($TumorIndices.Count -eq 0) {
        return @{
            DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            FieldList = $FieldList
            CustomFields = @{}
        }
    }

    # Initialize dictionary if needed
    Initialize-NaaccrDictionary | Out-Null
    
    # Track selected fields and custom fields
    $selectedFields = [System.Collections.ArrayList]@()
    $customFieldParents = @{}
    $script:isPopulatingFields = $false  # Flag to prevent recursive event handling (script scope for event access)
    
    # Copy TumorIndices to script scope for access from scriptblocks
    $script:previewTumorIndices = @($TumorIndices)
    
    # Initialize with provided field list
    foreach ($fieldId in $FieldList) {
        [void]$selectedFields.Add($fieldId)
    }

    # Create main form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = $Title
    $previewForm.Width = 1500
    $previewForm.Height = 750
    $previewForm.StartPosition = "CenterScreen"
    $previewForm.MinimumSize = New-Object System.Drawing.Size(1000, 500)

    # Main split container - left (field selector) | right (preview)
    $mainSplit = New-Object System.Windows.Forms.SplitContainer
    $mainSplit.Dock = 'Fill'
    $mainSplit.Orientation = 'Vertical'
    $mainSplit.Panel1MinSize = 250
    # Panel2MinSize and SplitterDistance set in Shown event to avoid size conflicts

    # ===== LEFT PANEL: Field Selector =====
    $leftPanel = New-Object System.Windows.Forms.Panel
    $leftPanel.Dock = 'Fill'
    $leftPanel.Padding = New-Object System.Windows.Forms.Padding(5)

    # Search box
    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Search fields:"
    $lblSearch.Location = New-Object System.Drawing.Point(5, 5)
    $lblSearch.AutoSize = $true

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(5, 25)
    $txtSearch.Width = 330
    $txtSearch.Anchor = 'Top,Left,Right'

    # Field list (CheckedListBox)
    $lblFields = New-Object System.Windows.Forms.Label
    $lblFields.Text = "Available Fields:"
    $lblFields.Location = New-Object System.Drawing.Point(5, 55)
    $lblFields.AutoSize = $true

    $lstFields = New-Object System.Windows.Forms.CheckedListBox
    $lstFields.Location = New-Object System.Drawing.Point(5, 75)
    $lstFields.Size = New-Object System.Drawing.Size(330, 450)
    $lstFields.Anchor = 'Top,Left,Right,Bottom'
    $lstFields.CheckOnClick = $true

    # Buttons panel for field actions
    $pnlFieldButtons = New-Object System.Windows.Forms.Panel
    $pnlFieldButtons.Location = New-Object System.Drawing.Point(5, 530)
    $pnlFieldButtons.Size = New-Object System.Drawing.Size(330, 80)
    $pnlFieldButtons.Anchor = 'Bottom,Left,Right'

    $btnAddCustom = New-Object System.Windows.Forms.Button
    $btnAddCustom.Text = "+ Custom Field"
    $btnAddCustom.Location = New-Object System.Drawing.Point(0, 0)
    $btnAddCustom.Width = 105

    $btnLoadConfig = New-Object System.Windows.Forms.Button
    $btnLoadConfig.Text = "Load Config"
    $btnLoadConfig.Location = New-Object System.Drawing.Point(110, 0)
    $btnLoadConfig.Width = 105

    $btnSaveConfig = New-Object System.Windows.Forms.Button
    $btnSaveConfig.Text = "Save Config"
    $btnSaveConfig.Location = New-Object System.Drawing.Point(220, 0)
    $btnSaveConfig.Width = 105

    $btnMoveUp = New-Object System.Windows.Forms.Button
    $btnMoveUp.Text = "Move Up"
    $btnMoveUp.Location = New-Object System.Drawing.Point(0, 35)
    $btnMoveUp.Width = 80

    $btnMoveDown = New-Object System.Windows.Forms.Button
    $btnMoveDown.Text = "Move Down"
    $btnMoveDown.Location = New-Object System.Drawing.Point(85, 35)
    $btnMoveDown.Width = 80

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh Preview"
    $btnRefresh.Location = New-Object System.Drawing.Point(170, 35)
    $btnRefresh.Width = 155

    $pnlFieldButtons.Controls.AddRange(@($btnAddCustom, $btnLoadConfig, $btnSaveConfig, $btnMoveUp, $btnMoveDown, $btnRefresh))
    $leftPanel.Controls.AddRange(@($lblSearch, $txtSearch, $lblFields, $lstFields, $pnlFieldButtons))

    # ===== RIGHT PANEL: Preview =====
    $rightPanel = New-Object System.Windows.Forms.Panel
    $rightPanel.Dock = 'Fill'
    $rightPanel.Padding = New-Object System.Windows.Forms.Padding(5)

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(5, 5)
    $lblSummary.Size = New-Object System.Drawing.Size(1100, 30)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblSummary.Anchor = 'Top,Left,Right'

    # DataGridView for preview
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(5, 40)
    $grid.Size = New-Object System.Drawing.Size(1100, 560)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "DisplayedCells"
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Both

    # Error label
    $lblErrors = New-Object System.Windows.Forms.Label
    $lblErrors.Location = New-Object System.Drawing.Point(5, 605)
    $lblErrors.Size = New-Object System.Drawing.Size(1100, 25)
    $lblErrors.ForeColor = [System.Drawing.Color]::Red
    $lblErrors.Anchor = 'Bottom,Left,Right'

    $rightPanel.Controls.AddRange(@($lblSummary, $grid, $lblErrors))

    # ===== BOTTOM PANEL: Action buttons =====
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = 'Bottom'
    $bottomPanel.Height = 50
    $bottomPanel.Padding = New-Object System.Windows.Forms.Padding(10)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = "Export"
    $btnExport.Width = 100
    $btnExport.Location = New-Object System.Drawing.Point(10, 10)
    $btnExport.Anchor = 'Bottom,Left'
    $btnExport.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(120, 10)
    $btnCancel.Anchor = 'Bottom,Left'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $bottomPanel.Controls.AddRange(@($btnExport, $btnCancel))

    # Wire up split containers
    $mainSplit.Panel1.Controls.Add($leftPanel)
    $mainSplit.Panel2.Controls.Add($rightPanel)

    $previewForm.Controls.Add($mainSplit)
    $previewForm.Controls.Add($bottomPanel)
    $previewForm.CancelButton = $btnCancel
    $previewForm.AcceptButton = $btnExport

    # ===== HELPER FUNCTIONS =====

    # Function to extract XmlId from display text
    $extractXmlId = {
        param([string]$DisplayText)
        
        if ($DisplayText -match '\(([^)]+)\)$') {
            return $matches[1]
        }
        elseif ($DisplayText -match '^CUSTOM - (.+)$') {
            return $matches[1]
        }
        return $null
    }

    # Function to populate the field list
    $populateFieldList = {
        param([string]$SearchFilter = "")
        
        # Set flag to prevent ItemCheck events from firing during population
        $script:isPopulatingFields = $true
        
        try {
            $lstFields.BeginUpdate()
            $lstFields.Items.Clear()
            $allItems = Get-NaaccrDictionary
            
            # Filter if search text provided
            if (-not [string]::IsNullOrWhiteSpace($SearchFilter)) {
                $searchLower = $SearchFilter.ToLower()
                $allItems = $allItems | Where-Object {
                    $_.Name.ToLower().Contains($searchLower) -or
                    $_.XmlId.ToLower().Contains($searchLower) -or
                    $_.Number -eq $SearchFilter
                }
            }
            
            # Add selected fields first (pinned to top)
            $addedIds = @{}
            
            # Section header for selected
            if ($selectedFields.Count -gt 0 -and [string]::IsNullOrWhiteSpace($SearchFilter)) {
                [void]$lstFields.Items.Add("== SELECTED FIELDS ==")
            }
            
            foreach ($fieldId in $selectedFields) {
                $item = Get-NaaccrItemByXmlId -XmlId $fieldId
                if ($null -ne $item) {
                    $displayText = "$($item.Number) - $($item.Name) ($($item.XmlId))"
                }
                else {
                    # Custom field
                    $displayText = "CUSTOM - $fieldId"
                }
                
                # Only show if matches filter or no filter
                if ([string]::IsNullOrWhiteSpace($SearchFilter) -or 
                    $displayText.ToLower().Contains($SearchFilter.ToLower())) {
                    $index = $lstFields.Items.Add($displayText)
                    $lstFields.SetItemChecked($index, $true)
                    $addedIds[$fieldId] = $true
                }
            }
            
            # Section header for available
            if ([string]::IsNullOrWhiteSpace($SearchFilter) -and $allItems.Count -gt 0) {
                [void]$lstFields.Items.Add("== AVAILABLE FIELDS ==")
            }
            
            # Add remaining items (not yet selected)
            foreach ($item in $allItems) {
                if (-not $addedIds.ContainsKey($item.XmlId)) {
                    $displayText = "$($item.Number) - $($item.Name) ($($item.XmlId))"
                    [void]$lstFields.Items.Add($displayText)
                    # Not checked - it's available but not selected
                }
            }
            
            $lstFields.EndUpdate()
        }
        finally {
            $script:isPopulatingFields = $false
        }
    }

    # Function to update preview
    $updatePreview = {
        $errors = @()
        $rows = @()
        
        # Get current field list from selected fields
        $currentFields = [array]$selectedFields
        
        if ($currentFields.Count -eq 0) {
            $lblSummary.Text = "No fields selected"
            $grid.DataSource = $null
            return
        }
        
        try {
            # Build preview rows - use script-scoped variable for proper access
            foreach ($tumorIndex in $script:previewTumorIndices) {
                if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) {
                    $errors += "Invalid tumor index: $tumorIndex"
                    continue
                }

                $tumor = $script:Tumors[$tumorIndex]
                $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

                if ($null -eq $patient) {
                    $errors += "Tumor at index $tumorIndex has no parent Patient node"
                    continue
                }

                # Build row data
                $row = @{}
                
                foreach ($fieldId in $currentFields) {
                    $value = ""
                    
                    # Get parent element from dictionary or custom fields
                    $parentElement = Get-NaaccrParentElement -XmlId $fieldId -CustomFields $customFieldParents
                    
                    if ($parentElement -eq "Patient") {
                        $node = $patient.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                        if ($null -ne $node) {
                            $value = $node.InnerText
                        }
                    }
                    else {
                        # Tumor-level or NaaccrData-level (treat as tumor for this context)
                        $node = $tumor.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                        if ($null -ne $node) {
                            $value = $node.InnerText
                        }
                    }
                    
                    $row[$fieldId] = $value
                }
                
                $rows += $row
            }
        }
        catch {
            $errors += "Error building preview: $($_.Exception.Message)"
        }
        
        # Update summary
        $lblSummary.Text = "Preview: $($rows.Count) row(s) with $($currentFields.Count) column(s)"
        if ($errors.Count -gt 0) {
            $lblSummary.Text += " | Errors: $($errors.Count)"
            $lblErrors.Text = "Errors: " + ($errors[0..([Math]::Min(2, $errors.Count - 1))] -join "; ")
        }
        else {
            $lblErrors.Text = ""
        }
        
        # Build DataTable
        $table = New-Object System.Data.DataTable
        
        foreach ($fieldId in $currentFields) {
            [void]$table.Columns.Add($fieldId, [string])
        }

        foreach ($row in $rows) {
            $dataRow = $table.NewRow()
            foreach ($fieldId in $currentFields) {
                $value = $row[$fieldId]
                if ($null -eq $value) {
                    $value = ""
                }
                $dataRow[$fieldId] = $value
            }
            [void]$table.Rows.Add($dataRow)
        }

        $grid.DataSource = $table
    }

    # ===== EVENT HANDLERS =====

    # Search text changed - use a simple debounce by checking if still typing
    $txtSearch.Add_TextChanged({
        & $populateFieldList $txtSearch.Text
    })

    # Item check changed - only process if not during population
    $lstFields.Add_ItemCheck({
        param($sender, $e)
        
        # Skip if we're populating the list programmatically
        if ($script:isPopulatingFields) {
            return
        }
        
        $itemText = $lstFields.Items[$e.Index]
        
        # Ignore section headers
        if ($itemText -match "^==") {
            $e.NewValue = $e.CurrentValue
            return
        }
        
        $xmlId = & $extractXmlId $itemText
        
        if ($null -eq $xmlId) {
            return
        }
        
        if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
            if (-not $selectedFields.Contains($xmlId)) {
                [void]$selectedFields.Add($xmlId)
            }
        }
        else {
            $selectedFields.Remove($xmlId)
        }
        
        # Update the preview after field selection changes
        & $updatePreview
    })

    # Add custom field
    $btnAddCustom.Add_Click({
        $customForm = New-Object System.Windows.Forms.Form
        $customForm.Text = "Add Custom Field"
        $customForm.Width = 400
        $customForm.Height = 200
        $customForm.StartPosition = "CenterParent"
        $customForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $customForm.MaximizeBox = $false
        $customForm.MinimizeBox = $false

        $lblXmlId = New-Object System.Windows.Forms.Label
        $lblXmlId.Text = "XML NAACCR ID:"
        $lblXmlId.Location = New-Object System.Drawing.Point(10, 20)
        $lblXmlId.AutoSize = $true

        $txtXmlId = New-Object System.Windows.Forms.TextBox
        $txtXmlId.Location = New-Object System.Drawing.Point(130, 17)
        $txtXmlId.Width = 240

        $lblParent = New-Object System.Windows.Forms.Label
        $lblParent.Text = "Parent Element:"
        $lblParent.Location = New-Object System.Drawing.Point(10, 55)
        $lblParent.AutoSize = $true

        $cmbParent = New-Object System.Windows.Forms.ComboBox
        $cmbParent.Location = New-Object System.Drawing.Point(130, 52)
        $cmbParent.Width = 240
        $cmbParent.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cmbParent.Items.AddRange(@("Tumor", "Patient", "NaaccrData"))
        $cmbParent.SelectedIndex = 0

        $btnAddOk = New-Object System.Windows.Forms.Button
        $btnAddOk.Text = "Add"
        $btnAddOk.Location = New-Object System.Drawing.Point(130, 100)
        $btnAddOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnAddCancel = New-Object System.Windows.Forms.Button
        $btnAddCancel.Text = "Cancel"
        $btnAddCancel.Location = New-Object System.Drawing.Point(220, 100)
        $btnAddCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $customForm.Controls.AddRange(@($lblXmlId, $txtXmlId, $lblParent, $cmbParent, $btnAddOk, $btnAddCancel))
        $customForm.AcceptButton = $btnAddOk
        $customForm.CancelButton = $btnAddCancel

        if ($customForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $newXmlId = $txtXmlId.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($newXmlId)) {
                if (-not $selectedFields.Contains($newXmlId)) {
                    [void]$selectedFields.Add($newXmlId)
                    $customFieldParents[$newXmlId] = $cmbParent.SelectedItem
                    & $populateFieldList $txtSearch.Text
                    & $updatePreview
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Field '$newXmlId' is already selected.", "Duplicate Field")
                }
            }
        }
    })

    # Load configuration
    $btnLoadConfig.Add_Click({
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "JSON Files (*.json)|*.json|All files (*.*)|*.*"
        $openFileDialog.Title = "Load Export Configuration"
        $openFileDialog.InitialDirectory = Get-ExportConfigPath

        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $result = Get-ExportConfig -FilePath $openFileDialog.FileName
            
            if ($result.Success) {
                $selectedFields.Clear()
                $customFieldParents.Clear()
                
                foreach ($field in $result.Config.Fields) {
                    [void]$selectedFields.Add($field.XmlId)
                    if ($field.IsCustom -eq $true -and $field.ContainsKey("ParentElement")) {
                        $customFieldParents[$field.XmlId] = $field.ParentElement
                    }
                }
                
                & $populateFieldList $txtSearch.Text
                & $updatePreview
                
                [System.Windows.Forms.MessageBox]::Show(
                    "Loaded configuration: $($result.Config.Name)`nFields: $($selectedFields.Count)",
                    "Configuration Loaded",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    $result.Message,
                    "Load Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    })

    # Save configuration
    $btnSaveConfig.Add_Click({
        $saveForm = New-Object System.Windows.Forms.Form
        $saveForm.Text = "Save Export Configuration"
        $saveForm.Width = 400
        $saveForm.Height = 150
        $saveForm.StartPosition = "CenterParent"
        $saveForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $saveForm.MaximizeBox = $false
        $saveForm.MinimizeBox = $false

        $lblName = New-Object System.Windows.Forms.Label
        $lblName.Text = "Configuration Name:"
        $lblName.Location = New-Object System.Drawing.Point(10, 20)
        $lblName.AutoSize = $true

        $txtName = New-Object System.Windows.Forms.TextBox
        $txtName.Location = New-Object System.Drawing.Point(140, 17)
        $txtName.Width = 230

        $btnSaveOk = New-Object System.Windows.Forms.Button
        $btnSaveOk.Text = "Save"
        $btnSaveOk.Location = New-Object System.Drawing.Point(140, 60)
        $btnSaveOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnSaveCancel = New-Object System.Windows.Forms.Button
        $btnSaveCancel.Text = "Cancel"
        $btnSaveCancel.Location = New-Object System.Drawing.Point(230, 60)
        $btnSaveCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $saveForm.Controls.AddRange(@($lblName, $txtName, $btnSaveOk, $btnSaveCancel))
        $saveForm.AcceptButton = $btnSaveOk
        $saveForm.CancelButton = $btnSaveCancel

        if ($saveForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $configName = $txtName.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($configName)) {
                $configName = "Unnamed_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
            }

            # Build fields array
            $fieldsArray = @()
            foreach ($fieldId in $selectedFields) {
                $fieldObj = @{
                    XmlId = $fieldId
                    IsCustom = $customFieldParents.ContainsKey($fieldId)
                }
                if ($fieldObj.IsCustom) {
                    $fieldObj.ParentElement = $customFieldParents[$fieldId]
                }
                $fieldsArray += $fieldObj
            }

            $config = New-ExportConfig -Name $configName -Fields $fieldsArray -Version 25
            $result = Save-ExportConfig -Config $config

            if ($result.Success) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Configuration saved to:`n$($result.Path)",
                    "Configuration Saved",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    $result.Message,
                    "Save Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    })

    # Move up
    $btnMoveUp.Add_Click({
        $selectedIndex = $lstFields.SelectedIndex
        if ($selectedIndex -le 0) { return }
        
        $itemText = $lstFields.Items[$selectedIndex]
        if ($itemText -match "^══") { return }
        
        $xmlId = & $extractXmlId $itemText
        if ($null -eq $xmlId) { return }
        
        $currentIndex = $selectedFields.IndexOf($xmlId)
        if ($currentIndex -gt 0) {
            $selectedFields.RemoveAt($currentIndex)
            $selectedFields.Insert($currentIndex - 1, $xmlId)
            & $populateFieldList $txtSearch.Text
            & $updatePreview
        }
    })

    # Move down
    $btnMoveDown.Add_Click({
        $selectedIndex = $lstFields.SelectedIndex
        if ($selectedIndex -lt 0) { return }
        
        $itemText = $lstFields.Items[$selectedIndex]
        if ($itemText -match "^══") { return }
        
        $xmlId = & $extractXmlId $itemText
        if ($null -eq $xmlId) { return }
        
        $currentIndex = $selectedFields.IndexOf($xmlId)
        if ($currentIndex -ge 0 -and $currentIndex -lt ($selectedFields.Count - 1)) {
            $selectedFields.RemoveAt($currentIndex)
            $selectedFields.Insert($currentIndex + 1, $xmlId)
            & $populateFieldList $txtSearch.Text
            & $updatePreview
        }
    })

    # Refresh preview
    $btnRefresh.Add_Click({
        & $updatePreview
    })

    # Form shown handler - set splitter distance after form is visible
    $previewForm.Add_Shown({
        $mainSplit.Panel2MinSize = 400
        $mainSplit.SplitterDistance = 350
        & $populateFieldList
        & $updatePreview
    })

    # Form closing handler
    $previewForm.Add_FormClosing({
        param($sender, $e)
        if ($sender.DialogResult -eq [System.Windows.Forms.DialogResult]::None) {
            $sender.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
    })

    # Show dialog
    $dialogResult = $previewForm.ShowDialog()

    # Return result with field list and custom fields
    return @{
        DialogResult = $dialogResult
        FieldList = [array]$selectedFields
        CustomFields = $customFieldParents
    }
}

function Show-XmlExportPreview {
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$Title = "Export XML Preview"
    )

    if ($TumorIndices.Count -eq 0) {
        return [System.Windows.Forms.DialogResult]::Cancel
    }

    $errors = @()
    $patientsMap = @{}  # Patient node -> array of tumor indices

    try {
        # Group tumors by patient - same logic as export
        foreach ($tumorIndex in $TumorIndices) {
            if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) {
                $errors += "Invalid tumor index: $tumorIndex"
                continue
            }

            $tumor = $script:Tumors[$tumorIndex]
            $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

            if ($null -eq $patient) {
                $errors += "Tumor at index $tumorIndex has no parent Patient node"
                continue
            }

            if (-not $patientsMap.ContainsKey($patient)) {
                $patientsMap[$patient] = @()
            }
            $patientsMap[$patient] += $tumorIndex
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error building preview: $($_.Exception.Message)",
            "Preview Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return [System.Windows.Forms.DialogResult]::Cancel
    }

    # Create preview form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = $Title
    $previewForm.Width = 1400
    $previewForm.Height = 700
    $previewForm.StartPosition = "CenterScreen"
    $previewForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $previewForm.MaximizeBox = $false
    $previewForm.MinimizeBox = $false

    # Summary label
    $uniquePatients = $patientsMap.Keys.Count
    $totalTumors = $TumorIndices.Count
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Preview: {0} patient(s) with {1} tumor(s) will be exported" -f $uniquePatients, $totalTumors
    if ($errors.Count -gt 0) {
        $lblSummary.Text += " | Errors: $($errors.Count)"
    }
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # DataGridView for preview
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 60)
    $grid.Size = New-Object System.Drawing.Size(1360, 500)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "AllCells"
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false

    # Build DataTable showing patient info and tumors
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientID", [string])
    [void]$table.Columns.Add("NameLast", [string])
    [void]$table.Columns.Add("NameFirst", [string])
    [void]$table.Columns.Add("TumorIndices", [string])
    [void]$table.Columns.Add("TumorCount", [int])
    [void]$table.Columns.Add("DateOfDiagnosis", [string])
    [void]$table.Columns.Add("PathReportNumber1", [string])

    # Populate table with patient and tumor info
    foreach ($patientNode in $patientsMap.Keys) {
        $tumorIndicesForPatient = $patientsMap[$patientNode]
        
        # Get patient info
        $patientId = ""
        $nameLast = ""
        $nameFirst = ""
        
        $patientIdNode = $patientNode.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $NsMgr)
        if ($null -ne $patientIdNode) {
            $patientId = $patientIdNode.InnerText
        }
        
        $nameLastNode = $patientNode.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
        if ($null -ne $nameLastNode) {
            $nameLast = $nameLastNode.InnerText
        }
        
        $nameFirstNode = $patientNode.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
        if ($null -ne $nameFirstNode) {
            $nameFirst = $nameFirstNode.InnerText
        }
        
        # Get tumor info (show first tumor's key fields, or combine if multiple)
        $tumorIndicesStr = ($tumorIndicesForPatient | ForEach-Object { ($_ + 1).ToString() }) -join ", "
        $datesOfDiagnosis = @()
        $pathReportNumbers = @()
        
        foreach ($tumorIndex in $tumorIndicesForPatient) {
            $tumor = $script:Tumors[$tumorIndex]
            
            $dateNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $NsMgr)
            if ($null -ne $dateNode) {
                $datesOfDiagnosis += $dateNode.InnerText
            }
            
            $pathNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $NsMgr)
            if ($null -ne $pathNode) {
                $pathReportNumbers += $pathNode.InnerText
            }
        }
        
        $dateOfDiagnosis = ($datesOfDiagnosis | Where-Object { $_ -ne "" }) -join ", "
        $pathReportNumber1 = ($pathReportNumbers | Where-Object { $_ -ne "" }) -join ", "
        
        $row = $table.NewRow()
        $row["PatientID"] = $patientId
        $row["NameLast"] = $nameLast
        $row["NameFirst"] = $nameFirst
        $row["TumorIndices"] = $tumorIndicesStr
        $row["TumorCount"] = $tumorIndicesForPatient.Count
        $row["DateOfDiagnosis"] = $dateOfDiagnosis
        $row["PathReportNumber1"] = $pathReportNumber1
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Buttons
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "Export"
    $btnOK.Width = 100
    $btnOK.Location = New-Object System.Drawing.Point(10, 580)
    $btnOK.Anchor = 'Bottom,Left'
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(120, 580)
    $btnCancel.Anchor = 'Bottom,Left'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    # Set CancelButton so ESC key and X button work properly
    $previewForm.CancelButton = $btnCancel
    $previewForm.AcceptButton = $btnOK

    # Handle form closing (X button) to ensure DialogResult is set
    $previewForm.Add_FormClosing({
        param($sender, $e)
        if ($sender.DialogResult -eq [System.Windows.Forms.DialogResult]::None) {
            $sender.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
    })

    # Show errors if any
    if ($errors.Count -gt 0) {
        $lblErrors = New-Object System.Windows.Forms.Label
        $lblErrors.Location = New-Object System.Drawing.Point(10, 550)
        $lblErrors.Size = New-Object System.Drawing.Size(1360, 20)
        $lblErrors.Text = "Errors: " + ($errors -join "; ")
        $lblErrors.ForeColor = [System.Drawing.Color]::Red
        $previewForm.Controls.Add($lblErrors)
    }

    # Add controls to form
    $previewForm.Controls.AddRange(@($lblSummary, $grid, $btnOK, $btnCancel))

    # Show dialog and return result
    return $previewForm.ShowDialog()
}
