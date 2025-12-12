# export-preview.ps1
# Preview function for CSV exports

function Show-ExportPreview {
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [array]$FieldList,
        [string]$Title = "Export Preview"
    )

    if ($TumorIndices.Count -eq 0) {
        return [System.Windows.Forms.DialogResult]::Cancel
    }

    $errors = @()
    $rows = @()

    try {
        # Build preview rows - same logic as export
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

            # Build row data
            $row = @{}
            
            foreach ($fieldId in $FieldList) {
                $value = ""
                
                # Check if field is at patient level or tumor level
                # Patient-level fields
                $patientFields = @("patientIdNumber", "nameLast", "nameFirst", "nameMiddle", "dateOfBirth", "reportingFacility")
                
                if ($patientFields -contains $fieldId) {
                    $node = $patient.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                    if ($null -ne $node) {
                        $value = $node.InnerText
                    }
                }
                else {
                    # Tumor-level fields
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
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Preview: {0} row(s) will be exported with {1} column(s)" -f $rows.Count, $FieldList.Count
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

    # Build DataTable with same headers as CSV export
    $table = New-Object System.Data.DataTable
    
    foreach ($fieldId in $FieldList) {
        [void]$table.Columns.Add($fieldId, [string])
    }

    # Populate table with preview data
    foreach ($row in $rows) {
        $dataRow = $table.NewRow()
        foreach ($fieldId in $FieldList) {
            $value = $row[$fieldId]
            if ($null -eq $value) {
                $value = ""
            }
            $dataRow[$fieldId] = $value
        }
        [void]$table.Rows.Add($dataRow)
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

