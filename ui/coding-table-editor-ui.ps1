# coding-table-editor-ui.ps1
# UI dialog for coding table editor

function Show-CodingTableEditor {
    <#
    .SYNOPSIS
    Show a modal editor for a coding table

    .PARAMETER FilePath
    Path to the coding table file

    .PARAMETER TableType
    'laterality' for single-column, 'topography' for two-column

    .PARAMETER Title
    Window title suffix (e.g., "Laterality", "Topography")
    #>
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][ValidateSet('laterality','topography')][string]$TableType,
        [Parameter(Mandatory=$true)][string]$Title
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Load data
    try {
        $data = Read-CodingTableFile -Path $FilePath -TableType $TableType
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to load file: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # Track if data has been modified
    $script:IsDirty = $false
    $script:OriginalFilePath = $FilePath

    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Edit Coding Table: $Title"
    $form.Width = 700
    $form.Height = 600
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(500, 400)

    # File info label
    $lblFile = New-Object System.Windows.Forms.Label
    $lblFile.Location = New-Object System.Drawing.Point(10, 10)
    $lblFile.Size = New-Object System.Drawing.Size(660, 20)
    $lblFile.Text = "File: $FilePath"
    $lblFile.Anchor = 'Top,Left,Right'

    # Toolbar panel
    $toolPanel = New-Object System.Windows.Forms.Panel
    $toolPanel.Location = New-Object System.Drawing.Point(10, 35)
    $toolPanel.Size = New-Object System.Drawing.Size(660, 35)
    $toolPanel.Anchor = 'Top,Left,Right'

    $btnAddRow = New-Object System.Windows.Forms.Button
    $btnAddRow.Text = "Add Row"
    $btnAddRow.Location = New-Object System.Drawing.Point(0, 5)
    $btnAddRow.Width = 80

    $btnDeleteRow = New-Object System.Windows.Forms.Button
    $btnDeleteRow.Text = "Delete Selected"
    $btnDeleteRow.Location = New-Object System.Drawing.Point(90, 5)
    $btnDeleteRow.Width = 100

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(200, 10)
    $lblCount.AutoSize = $true
    $lblCount.Text = "Rows: $($data.Count)"

    $toolPanel.Controls.AddRange(@($btnAddRow, $btnDeleteRow, $lblCount))

    # DataGridView
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 75)
    $grid.Size = New-Object System.Drawing.Size(660, 430)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.AllowUserToAddRows = $true
    $grid.AllowUserToDeleteRows = $true
    $grid.ReadOnly = $false
    $grid.MultiSelect = $true
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.RowHeadersVisible = $true

    # Create DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Code", [string])

    if ($TableType -eq 'topography') {
        [void]$table.Columns.Add("SearchPhrase", [string])
    }

    # Load data into table
    foreach ($item in $data) {
        $row = $table.NewRow()
        $row["Code"] = $item.Code

        if ($TableType -eq 'topography') {
            $row["SearchPhrase"] = $item.SearchPhrase
        }

        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Configure columns
    if ($grid.Columns["Code"]) {
        $grid.Columns["Code"].Width = 100
        $grid.Columns["Code"].MinimumWidth = 80
    }

    if ($TableType -eq 'topography' -and $grid.Columns["SearchPhrase"]) {
        $grid.Columns["SearchPhrase"].AutoSizeMode = 'Fill'
    }

    # Button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(10, 515)
    $buttonPanel.Size = New-Object System.Drawing.Size(660, 40)
    $buttonPanel.Anchor = 'Bottom,Left,Right'

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(0, 5)
    $btnSave.Width = 80

    $btnSaveAs = New-Object System.Windows.Forms.Button
    $btnSaveAs.Text = "Save As..."
    $btnSaveAs.Location = New-Object System.Drawing.Point(90, 5)
    $btnSaveAs.Width = 80

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(180, 5)
    $btnCancel.Width = 80

    $buttonPanel.Controls.AddRange(@($btnSave, $btnSaveAs, $btnCancel))

    # Update row count function
    $updateRowCount = {
        $rowCount = 0
        foreach ($row in $table.Rows) {
            if ($row.RowState -ne [System.Data.DataRowState]::Deleted) {
                if (-not [string]::IsNullOrWhiteSpace($row["Code"])) {
                    $rowCount++
                }
            }
        }
        $lblCount.Text = "Rows: $rowCount"
    }

    # Get data from table function
    $getTableData = {
        $items = @()
        foreach ($row in $table.Rows) {
            if ($row.RowState -eq [System.Data.DataRowState]::Deleted) { continue }

            $code = [string]$row["Code"]
            if ([string]::IsNullOrWhiteSpace($code)) { continue }

            # Format the code
            $formattedCode = Format-SiteCode -Code $code

            if ($TableType -eq 'topography') {
                $items += [PSCustomObject]@{
                    Code = $formattedCode
                    SearchPhrase = [string]$row["SearchPhrase"]
                }
            }
            else {
                $items += [PSCustomObject]@{
                    Code = $formattedCode
                }
            }
        }
        return $items
    }

    # Track changes
    $table.Add_RowChanged({
        $script:IsDirty = $true
        & $updateRowCount
    })

    $table.Add_RowDeleted({
        $script:IsDirty = $true
        & $updateRowCount
    })

    $table.Add_TableNewRow({
        $script:IsDirty = $true
    })

    # Add Row button
    $btnAddRow.Add_Click({
        $newRow = $table.NewRow()
        $newRow["Code"] = ""
        if ($TableType -eq 'topography') {
            $newRow["SearchPhrase"] = ""
        }
        [void]$table.Rows.Add($newRow)

        # Select the new row
        $grid.ClearSelection()
        $lastRowIndex = $grid.Rows.Count - 2  # -2 because of the "new row" placeholder
        if ($lastRowIndex -ge 0) {
            $grid.Rows[$lastRowIndex].Selected = $true
            $grid.CurrentCell = $grid.Rows[$lastRowIndex].Cells[0]
            $grid.BeginEdit($true)
        }

        $script:IsDirty = $true
        & $updateRowCount
    })

    # Delete Row button
    $btnDeleteRow.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please select one or more rows to delete.",
                "No Selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Delete $($grid.SelectedRows.Count) selected row(s)?",
            "Confirm Delete",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Get indices to delete (in reverse order to avoid index shifting)
            $indicesToDelete = @()
            foreach ($row in $grid.SelectedRows) {
                if (-not $row.IsNewRow) {
                    $indicesToDelete += $row.Index
                }
            }

            $indicesToDelete = $indicesToDelete | Sort-Object -Descending

            foreach ($idx in $indicesToDelete) {
                if ($idx -ge 0 -and $idx -lt $table.Rows.Count) {
                    $table.Rows[$idx].Delete()
                }
            }

            $script:IsDirty = $true
            & $updateRowCount
        }
    })

    # Save button
    $btnSave.Add_Click({
        try {
            # End any current edit
            $grid.EndEdit()

            $items = & $getTableData

            if ($items.Count -eq 0) {
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "The table is empty. Save anyway?",
                    "Empty Table",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )

                if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                    return
                }
            }

            Write-CodingTableFile -Path $script:OriginalFilePath -TableType $TableType -Data $items

            $script:IsDirty = $false

            [System.Windows.Forms.MessageBox]::Show(
                "File saved successfully.`n`n$($script:OriginalFilePath)",
                "Saved",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to save file: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    # Save As button
    $btnSaveAs.Add_Click({
        try {
            # End any current edit
            $grid.EndEdit()

            $items = & $getTableData

            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Title = "Save Coding Table As"
            $saveDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:OriginalFilePath)

            if ($TableType -eq 'laterality') {
                $saveDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
                $saveDialog.DefaultExt = "json"
                $saveDialog.FileName = [System.IO.Path]::GetFileName($script:OriginalFilePath)
            }
            else {
                $saveDialog.Filter = "JSONL Files (*.jsonl)|*.jsonl|All Files (*.*)|*.*"
                $saveDialog.DefaultExt = "jsonl"
                $saveDialog.FileName = [System.IO.Path]::GetFileName($script:OriginalFilePath)
            }

            if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                Write-CodingTableFile -Path $saveDialog.FileName -TableType $TableType -Data $items

                $script:IsDirty = $false
                $script:OriginalFilePath = $saveDialog.FileName
                $lblFile.Text = "File: $($saveDialog.FileName)"

                [System.Windows.Forms.MessageBox]::Show(
                    "File saved successfully.`n`n$($saveDialog.FileName)",
                    "Saved",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to save file: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    # Cancel button
    $btnCancel.Add_Click({
        if ($script:IsDirty) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "You have unsaved changes. Discard them?",
                "Unsaved Changes",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )

            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }

        $form.Close()
    })

    # Form closing handler
    $form.Add_FormClosing({
        param($eventSender, $e)

        if ($script:IsDirty) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "You have unsaved changes. Discard them?",
                "Unsaved Changes",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )

            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
            }
        }
    })

    # Add controls to form
    $form.Controls.AddRange(@($lblFile, $toolPanel, $grid, $buttonPanel))

    # Show form
    [void]$form.ShowDialog()
}
