# btnManagePriorityPatterns.ps1
# Priority Patterns Editor - Manage site coding heuristics with AND/OR logic support

$script:PriorityPatternsFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "data\dictionaries\PriorityPatterns.jsonl"

function Read-PriorityPatternsFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @()
    }

    $patterns = @()
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    # Remove BOM if present
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }
    $lines = $content -split "`r?`n"

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $pattern = $line | ConvertFrom-Json
            # Only add valid patterns (must have a Code)
            if (-not [string]::IsNullOrWhiteSpace($pattern.Code)) {
                $patterns += $pattern
            }
        }
        catch {
            Write-Warning "Failed to parse priority pattern line: $line - $($_.Exception.Message)"
        }
    }

    return $patterns
}

function Write-PriorityPatternsFile {
    param(
        [string]$Path,
        [array]$Patterns
    )

    $lines = @()
    foreach ($pattern in $Patterns) {
        # Allow {topo} as special Code for dynamic lookup, or any non-empty Code
        $code = $pattern.Code
        if (-not [string]::IsNullOrWhiteSpace($code) -or $code -eq "{topo}") {
            $lines += ($pattern | ConvertTo-Json -Compress -Depth 10)
        }
        elseif ($pattern.Expression) {
            # Check if pattern has topo-template expressions - save even with empty Code
            $hasTopoTemplate = $false
            foreach ($expr in $pattern.Expression) {
                if ($expr.type -eq "topo-template") {
                    $hasTopoTemplate = $true
                    break
                }
            }
            if ($hasTopoTemplate) {
                # Default Code to {topo} for topo-template patterns
                $pattern.Code = "{topo}"
                $lines += ($pattern | ConvertTo-Json -Compress -Depth 10)
            }
        }
    }

    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::UTF8)
}

function Get-ExpressionPreview {
    param($Expression, $Logic)

    # Handle null or empty
    if ($null -eq $Expression) {
        return "(no terms)"
    }

    # Ensure it's an array we can iterate
    $exprArray = @($Expression)
    if ($exprArray.Count -eq 0) {
        return "(no terms)"
    }

    $parts = @()
    foreach ($item in $exprArray) {
        if ($null -eq $item) { continue }

        $itemType = $item.type
        if ($itemType -eq "term") {
            $parts += $item.value
        }
        elseif ($itemType -eq "group") {
            $termsArray = @($item.terms)
            $groupTerms = $termsArray -join " $($item.logic) "
            $parts += "($groupTerms)"
        }
        elseif ($itemType -eq "topo-template") {
            $parts += "{topo}: $($item.template)"
        }
    }

    if ($parts.Count -eq 0) {
        return "(no terms)"
    }

    $preview = $parts -join " $Logic "
    if ($preview.Length -gt 50) {
        $preview = $preview.Substring(0, 47) + "..."
    }

    return $preview
}

function Show-PatternEditDialog {
    param(
        [PSCustomObject]$Pattern,
        [string]$Title = "Edit Pattern"
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.Width = 600
    $dialog.Height = 500
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    # Site Code
    $lblCode = New-Object System.Windows.Forms.Label
    $lblCode.Text = "Site Code:"
    $lblCode.Location = New-Object System.Drawing.Point(15, 20)
    $lblCode.AutoSize = $true

    $txtCode = New-Object System.Windows.Forms.TextBox
    $txtCode.Location = New-Object System.Drawing.Point(100, 17)
    $txtCode.Width = 80
    $txtCode.Text = if ($Pattern) { $Pattern.Code } else { "" }

    # Priority
    $lblPriority = New-Object System.Windows.Forms.Label
    $lblPriority.Text = "Priority:"
    $lblPriority.Location = New-Object System.Drawing.Point(200, 20)
    $lblPriority.AutoSize = $true

    $numPriority = New-Object System.Windows.Forms.NumericUpDown
    $numPriority.Location = New-Object System.Drawing.Point(260, 17)
    $numPriority.Width = 60
    $numPriority.Minimum = 1
    $numPriority.Maximum = 999
    $numPriority.Value = if ($Pattern -and $Pattern.Priority) { [int]$Pattern.Priority } else { 1 }

    # Enabled checkbox
    $chkEnabled = New-Object System.Windows.Forms.CheckBox
    $chkEnabled.Text = "Enabled"
    $chkEnabled.Location = New-Object System.Drawing.Point(340, 18)
    $chkEnabled.Checked = if ($Pattern) { $Pattern.Enabled -ne $false } else { $true }
    $chkEnabled.AutoSize = $true

    # Force Laterality checkbox
    $chkForceLat = New-Object System.Windows.Forms.CheckBox
    $chkForceLat.Text = "Force Laterality = 9 (Unknown)"
    $chkForceLat.Location = New-Object System.Drawing.Point(15, 50)
    $chkForceLat.Checked = if ($Pattern -and $Pattern.ForceLaterality) { $true } else { $false }
    $chkForceLat.AutoSize = $true

    # Logic
    $grpLogic = New-Object System.Windows.Forms.GroupBox
    $grpLogic.Text = "Top-Level Logic"
    $grpLogic.Location = New-Object System.Drawing.Point(15, 75)
    $grpLogic.Size = New-Object System.Drawing.Size(555, 50)

    $rdoOr = New-Object System.Windows.Forms.RadioButton
    $rdoOr.Text = "Any term matches (OR)"
    $rdoOr.Location = New-Object System.Drawing.Point(15, 20)
    $rdoOr.AutoSize = $true
    $rdoOr.Checked = if ($Pattern) { $Pattern.Logic -ne "AND" } else { $true }

    $rdoAnd = New-Object System.Windows.Forms.RadioButton
    $rdoAnd.Text = "All terms match (AND)"
    $rdoAnd.Location = New-Object System.Drawing.Point(200, 20)
    $rdoAnd.AutoSize = $true
    $rdoAnd.Checked = if ($Pattern) { $Pattern.Logic -eq "AND" } else { $false }

    $grpLogic.Controls.AddRange(@($rdoOr, $rdoAnd))

    # Terms label
    $lblTerms = New-Object System.Windows.Forms.Label
    $lblTerms.Text = "Expression Terms:"
    $lblTerms.Location = New-Object System.Drawing.Point(15, 135)
    $lblTerms.AutoSize = $true

    # Terms listbox
    $lstTerms = New-Object System.Windows.Forms.ListBox
    $lstTerms.Location = New-Object System.Drawing.Point(15, 155)
    $lstTerms.Size = New-Object System.Drawing.Size(450, 200)
    $lstTerms.SelectionMode = "One"

    # Load existing terms
    $script:ExpressionItems = @()
    if ($Pattern -and $Pattern.Expression) {
        foreach ($item in $Pattern.Expression) {
            $script:ExpressionItems += $item
        }
    }

    $refreshTermsList = {
        $lstTerms.Items.Clear()
        foreach ($item in $script:ExpressionItems) {
            if ($item.type -eq "term") {
                $lstTerms.Items.Add($item.value)
            }
            elseif ($item.type -eq "group") {
                $groupDisplay = "[$($item.logic): $($item.terms -join ', ')]"
                $lstTerms.Items.Add($groupDisplay)
            }
            elseif ($item.type -eq "topo-template") {
                $lstTerms.Items.Add("{topo}: $($item.template)")
            }
        }
    }

    & $refreshTermsList

    # Term buttons panel
    $pnlTermButtons = New-Object System.Windows.Forms.Panel
    $pnlTermButtons.Location = New-Object System.Drawing.Point(475, 155)
    $pnlTermButtons.Size = New-Object System.Drawing.Size(95, 220)

    $btnAddTerm = New-Object System.Windows.Forms.Button
    $btnAddTerm.Text = "Add Term"
    $btnAddTerm.Location = New-Object System.Drawing.Point(0, 0)
    $btnAddTerm.Width = 90

    $btnAddAndGroup = New-Object System.Windows.Forms.Button
    $btnAddAndGroup.Text = "Add AND"
    $btnAddAndGroup.Location = New-Object System.Drawing.Point(0, 35)
    $btnAddAndGroup.Width = 90

    $btnAddOrGroup = New-Object System.Windows.Forms.Button
    $btnAddOrGroup.Text = "Add OR"
    $btnAddOrGroup.Location = New-Object System.Drawing.Point(0, 70)
    $btnAddOrGroup.Width = 90

    $btnAddTopoTemplate = New-Object System.Windows.Forms.Button
    $btnAddTopoTemplate.Text = "Add {topo}"
    $btnAddTopoTemplate.Location = New-Object System.Drawing.Point(0, 105)
    $btnAddTopoTemplate.Width = 90

    $btnEditTerm = New-Object System.Windows.Forms.Button
    $btnEditTerm.Text = "Edit"
    $btnEditTerm.Location = New-Object System.Drawing.Point(0, 150)
    $btnEditTerm.Width = 90

    $btnRemoveTerm = New-Object System.Windows.Forms.Button
    $btnRemoveTerm.Text = "Remove"
    $btnRemoveTerm.Location = New-Object System.Drawing.Point(0, 185)
    $btnRemoveTerm.Width = 90

    $pnlTermButtons.Controls.AddRange(@($btnAddTerm, $btnAddAndGroup, $btnAddOrGroup, $btnAddTopoTemplate, $btnEditTerm, $btnRemoveTerm))

    # Add Term handler
    $btnAddTerm.Add_Click({
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Add Term"
        $inputForm.Width = 400
        $inputForm.Height = 130
        $inputForm.StartPosition = "CenterParent"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = "Enter search phrase:"
        $lblInput.Location = New-Object System.Drawing.Point(15, 15)
        $lblInput.AutoSize = $true

        $txtInput = New-Object System.Windows.Forms.TextBox
        $txtInput.Location = New-Object System.Drawing.Point(15, 40)
        $txtInput.Width = 350

        $btnInputOk = New-Object System.Windows.Forms.Button
        $btnInputOk.Text = "OK"
        $btnInputOk.Location = New-Object System.Drawing.Point(205, 70)
        $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnInputCancel = New-Object System.Windows.Forms.Button
        $btnInputCancel.Text = "Cancel"
        $btnInputCancel.Location = New-Object System.Drawing.Point(290, 70)
        $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
        $inputForm.AcceptButton = $btnInputOk
        $inputForm.CancelButton = $btnInputCancel

        if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $term = $txtInput.Text.Trim().ToLower()
            if ($term) {
                $script:ExpressionItems += @{ type = "term"; value = $term }
                & $refreshTermsList
            }
        }
    })

    # Add AND Group handler
    $btnAddAndGroup.Add_Click({
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Add AND Group"
        $inputForm.Width = 400
        $inputForm.Height = 150
        $inputForm.StartPosition = "CenterParent"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = "Enter terms (comma-separated):`nAll terms must match for group to match."
        $lblInput.Location = New-Object System.Drawing.Point(15, 15)
        $lblInput.Size = New-Object System.Drawing.Size(350, 35)

        $txtInput = New-Object System.Windows.Forms.TextBox
        $txtInput.Location = New-Object System.Drawing.Point(15, 55)
        $txtInput.Width = 350

        $btnInputOk = New-Object System.Windows.Forms.Button
        $btnInputOk.Text = "OK"
        $btnInputOk.Location = New-Object System.Drawing.Point(205, 85)
        $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnInputCancel = New-Object System.Windows.Forms.Button
        $btnInputCancel.Text = "Cancel"
        $btnInputCancel.Location = New-Object System.Drawing.Point(290, 85)
        $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
        $inputForm.AcceptButton = $btnInputOk
        $inputForm.CancelButton = $btnInputCancel

        if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $termsStr = $txtInput.Text.Trim()
            if ($termsStr) {
                $terms = @($termsStr -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
                if ($terms.Count -ge 2) {
                    $script:ExpressionItems += @{ type = "group"; logic = "AND"; terms = $terms }
                    & $refreshTermsList
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("AND group requires at least 2 terms.", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                }
            }
        }
    })

    # Add OR Group handler
    $btnAddOrGroup.Add_Click({
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Add OR Group"
        $inputForm.Width = 400
        $inputForm.Height = 150
        $inputForm.StartPosition = "CenterParent"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = "Enter terms (comma-separated):`nAny term matching will satisfy the group."
        $lblInput.Location = New-Object System.Drawing.Point(15, 15)
        $lblInput.Size = New-Object System.Drawing.Size(350, 35)

        $txtInput = New-Object System.Windows.Forms.TextBox
        $txtInput.Location = New-Object System.Drawing.Point(15, 55)
        $txtInput.Width = 350

        $btnInputOk = New-Object System.Windows.Forms.Button
        $btnInputOk.Text = "OK"
        $btnInputOk.Location = New-Object System.Drawing.Point(205, 85)
        $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnInputCancel = New-Object System.Windows.Forms.Button
        $btnInputCancel.Text = "Cancel"
        $btnInputCancel.Location = New-Object System.Drawing.Point(290, 85)
        $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
        $inputForm.AcceptButton = $btnInputOk
        $inputForm.CancelButton = $btnInputCancel

        if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $termsStr = $txtInput.Text.Trim()
            if ($termsStr) {
                $terms = @($termsStr -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
                if ($terms.Count -ge 2) {
                    $script:ExpressionItems += @{ type = "group"; logic = "OR"; terms = $terms }
                    & $refreshTermsList
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("OR group requires at least 2 terms.", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                }
            }
        }
    })

    # Add Topo-Template handler
    $btnAddTopoTemplate.Add_Click({
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Add Topo-Template"
        $inputForm.Width = 450
        $inputForm.Height = 170
        $inputForm.StartPosition = "CenterParent"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = "Enter template with {topo} placeholder:`nExample: consistent with {topo} origin"
        $lblInput.Location = New-Object System.Drawing.Point(15, 15)
        $lblInput.Size = New-Object System.Drawing.Size(400, 35)

        $txtInput = New-Object System.Windows.Forms.TextBox
        $txtInput.Location = New-Object System.Drawing.Point(15, 55)
        $txtInput.Width = 400
        $txtInput.Text = "{topo}"

        $btnInputOk = New-Object System.Windows.Forms.Button
        $btnInputOk.Text = "OK"
        $btnInputOk.Location = New-Object System.Drawing.Point(255, 95)
        $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnInputCancel = New-Object System.Windows.Forms.Button
        $btnInputCancel.Text = "Cancel"
        $btnInputCancel.Location = New-Object System.Drawing.Point(340, 95)
        $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
        $inputForm.AcceptButton = $btnInputOk
        $inputForm.CancelButton = $btnInputCancel

        if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $template = $txtInput.Text.Trim().ToLower()
            if ($template -and $template.Contains("{topo}")) {
                $script:ExpressionItems += @{ type = "topo-template"; template = $template }
                & $refreshTermsList
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("Template must contain {topo} placeholder.", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
        }
    })

    # Edit Term handler
    $btnEditTerm.Add_Click({
        $idx = $lstTerms.SelectedIndex
        if ($idx -lt 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select an item to edit.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $item = $script:ExpressionItems[$idx]

        if ($item.type -eq "term") {
            $inputForm = New-Object System.Windows.Forms.Form
            $inputForm.Text = "Edit Term"
            $inputForm.Width = 400
            $inputForm.Height = 130
            $inputForm.StartPosition = "CenterParent"
            $inputForm.FormBorderStyle = "FixedDialog"
            $inputForm.MaximizeBox = $false
            $inputForm.MinimizeBox = $false

            $lblInput = New-Object System.Windows.Forms.Label
            $lblInput.Text = "Enter search phrase:"
            $lblInput.Location = New-Object System.Drawing.Point(15, 15)
            $lblInput.AutoSize = $true

            $txtInput = New-Object System.Windows.Forms.TextBox
            $txtInput.Location = New-Object System.Drawing.Point(15, 40)
            $txtInput.Width = 350
            $txtInput.Text = $item.value

            $btnInputOk = New-Object System.Windows.Forms.Button
            $btnInputOk.Text = "OK"
            $btnInputOk.Location = New-Object System.Drawing.Point(205, 70)
            $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

            $btnInputCancel = New-Object System.Windows.Forms.Button
            $btnInputCancel.Text = "Cancel"
            $btnInputCancel.Location = New-Object System.Drawing.Point(290, 70)
            $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

            $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
            $inputForm.AcceptButton = $btnInputOk
            $inputForm.CancelButton = $btnInputCancel

            if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $term = $txtInput.Text.Trim().ToLower()
                if ($term) {
                    $script:ExpressionItems[$idx] = @{ type = "term"; value = $term }
                    & $refreshTermsList
                }
            }
        }
        elseif ($item.type -eq "group") {
            $inputForm = New-Object System.Windows.Forms.Form
            $inputForm.Text = "Edit $($item.logic) Group"
            $inputForm.Width = 400
            $inputForm.Height = 150
            $inputForm.StartPosition = "CenterParent"
            $inputForm.FormBorderStyle = "FixedDialog"
            $inputForm.MaximizeBox = $false
            $inputForm.MinimizeBox = $false

            $lblInput = New-Object System.Windows.Forms.Label
            $lblInput.Text = "Enter terms (comma-separated):"
            $lblInput.Location = New-Object System.Drawing.Point(15, 15)
            $lblInput.AutoSize = $true

            $txtInput = New-Object System.Windows.Forms.TextBox
            $txtInput.Location = New-Object System.Drawing.Point(15, 40)
            $txtInput.Width = 350
            $txtInput.Text = $item.terms -join ", "

            $btnInputOk = New-Object System.Windows.Forms.Button
            $btnInputOk.Text = "OK"
            $btnInputOk.Location = New-Object System.Drawing.Point(205, 70)
            $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

            $btnInputCancel = New-Object System.Windows.Forms.Button
            $btnInputCancel.Text = "Cancel"
            $btnInputCancel.Location = New-Object System.Drawing.Point(290, 70)
            $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

            $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
            $inputForm.AcceptButton = $btnInputOk
            $inputForm.CancelButton = $btnInputCancel

            if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $termsStr = $txtInput.Text.Trim()
                if ($termsStr) {
                    $terms = @($termsStr -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
                    if ($terms.Count -ge 2) {
                        $script:ExpressionItems[$idx] = @{ type = "group"; logic = $item.logic; terms = $terms }
                        & $refreshTermsList
                    }
                }
            }
        }
        elseif ($item.type -eq "topo-template") {
            $inputForm = New-Object System.Windows.Forms.Form
            $inputForm.Text = "Edit Topo-Template"
            $inputForm.Width = 450
            $inputForm.Height = 170
            $inputForm.StartPosition = "CenterParent"
            $inputForm.FormBorderStyle = "FixedDialog"
            $inputForm.MaximizeBox = $false
            $inputForm.MinimizeBox = $false

            $lblInput = New-Object System.Windows.Forms.Label
            $lblInput.Text = "Enter template with {topo} placeholder:`nExample: consistent with {topo} origin"
            $lblInput.Location = New-Object System.Drawing.Point(15, 15)
            $lblInput.Size = New-Object System.Drawing.Size(400, 35)

            $txtInput = New-Object System.Windows.Forms.TextBox
            $txtInput.Location = New-Object System.Drawing.Point(15, 55)
            $txtInput.Width = 400
            $txtInput.Text = $item.template

            $btnInputOk = New-Object System.Windows.Forms.Button
            $btnInputOk.Text = "OK"
            $btnInputOk.Location = New-Object System.Drawing.Point(255, 95)
            $btnInputOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

            $btnInputCancel = New-Object System.Windows.Forms.Button
            $btnInputCancel.Text = "Cancel"
            $btnInputCancel.Location = New-Object System.Drawing.Point(340, 95)
            $btnInputCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

            $inputForm.Controls.AddRange(@($lblInput, $txtInput, $btnInputOk, $btnInputCancel))
            $inputForm.AcceptButton = $btnInputOk
            $inputForm.CancelButton = $btnInputCancel

            if ($inputForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $template = $txtInput.Text.Trim().ToLower()
                if ($template -and $template.Contains("{topo}")) {
                    $script:ExpressionItems[$idx] = @{ type = "topo-template"; template = $template }
                    & $refreshTermsList
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Template must contain {topo} placeholder.", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                }
            }
        }
    })

    # Remove Term handler
    $btnRemoveTerm.Add_Click({
        $idx = $lstTerms.SelectedIndex
        if ($idx -lt 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select an item to remove.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $result = [System.Windows.Forms.MessageBox]::Show("Remove this item?", "Confirm Remove", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $newItems = @()
            for ($i = 0; $i -lt $script:ExpressionItems.Count; $i++) {
                if ($i -ne $idx) {
                    $newItems += $script:ExpressionItems[$i]
                }
            }
            $script:ExpressionItems = $newItems
            & $refreshTermsList
        }
    })

    # OK and Cancel buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(400, 420)
    $btnOk.Width = 80
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(490, 420)
    $btnCancel.Width = 80
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblCode, $txtCode, $lblPriority, $numPriority, $chkEnabled, $chkForceLat, $grpLogic, $lblTerms, $lstTerms, $pnlTermButtons, $btnOk, $btnCancel))
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $code = $txtCode.Text.Trim().ToUpper()
        if ($code -match '^\d{1,3}$') {
            $code = "C" + $code.PadLeft(3, '0')
        }
        elseif ($code -match '^C\d{1,2}$') {
            $digits = $code.Substring(1)
            $code = "C" + $digits.PadLeft(3, '0')
        }

        return [PSCustomObject]@{
            Code = $code
            Priority = [int]$numPriority.Value
            Expression = $script:ExpressionItems
            Logic = if ($rdoAnd.Checked) { "AND" } else { "OR" }
            Enabled = $chkEnabled.Checked
            ForceLaterality = if ($chkForceLat.Checked) { "9" } else { $null }
            IsOverride = $false
        }
    }

    return $null
}

function Show-PriorityPatternsEditor {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $filePath = $script:PriorityPatternsFilePath

    # Load patterns
    try {
        $patterns = @(Read-PriorityPatternsFile -Path $filePath)
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

    $script:IsDirty = $false
    $script:CurrentPatterns = $patterns

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Edit Priority Patterns"
    $form.Width = 900
    $form.Height = 600
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(700, 400)

    # File info label
    $lblFile = New-Object System.Windows.Forms.Label
    $lblFile.Location = New-Object System.Drawing.Point(10, 10)
    $lblFile.Size = New-Object System.Drawing.Size(860, 20)
    $lblFile.Text = "File: $filePath"
    $lblFile.Anchor = 'Top,Left,Right'

    # Toolbar panel
    $toolPanel = New-Object System.Windows.Forms.Panel
    $toolPanel.Location = New-Object System.Drawing.Point(10, 35)
    $toolPanel.Size = New-Object System.Drawing.Size(860, 35)
    $toolPanel.Anchor = 'Top,Left,Right'

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add"
    $btnAdd.Location = New-Object System.Drawing.Point(0, 5)
    $btnAdd.Width = 70

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "Delete"
    $btnDelete.Location = New-Object System.Drawing.Point(80, 5)
    $btnDelete.Width = 70

    $btnMoveUp = New-Object System.Windows.Forms.Button
    $btnMoveUp.Text = "Move Up"
    $btnMoveUp.Location = New-Object System.Drawing.Point(160, 5)
    $btnMoveUp.Width = 75

    $btnMoveDown = New-Object System.Windows.Forms.Button
    $btnMoveDown.Text = "Move Down"
    $btnMoveDown.Location = New-Object System.Drawing.Point(245, 5)
    $btnMoveDown.Width = 85

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(350, 10)
    $lblCount.AutoSize = $true
    $lblCount.Text = "Rows: $($patterns.Count)"

    $toolPanel.Controls.AddRange(@($btnAdd, $btnDelete, $btnMoveUp, $btnMoveDown, $lblCount))

    # DataGridView
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 75)
    $grid.Size = New-Object System.Drawing.Size(860, 430)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.ReadOnly = $true
    $grid.MultiSelect = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.RowHeadersVisible = $false

    # Create DataTable first (before binding)
    $script:GridTable = New-Object System.Data.DataTable
    [void]$script:GridTable.Columns.Add("Priority", [string])
    [void]$script:GridTable.Columns.Add("Code", [string])
    [void]$script:GridTable.Columns.Add("Expression", [string])
    [void]$script:GridTable.Columns.Add("Lat=9", [string])
    [void]$script:GridTable.Columns.Add("Enabled", [string])

    # Load initial data (skip empty/invalid patterns)
    foreach ($pattern in $script:CurrentPatterns) {
        # Skip patterns without a Code (unless it's {topo})
        if ([string]::IsNullOrWhiteSpace($pattern.Code)) { continue }

        $preview = Get-ExpressionPreview -Expression $pattern.Expression -Logic $pattern.Logic
        $enabledText = if ($pattern.Enabled -eq $false) { "" } else { "true" }
        $forceLat = if ($pattern.ForceLaterality) { "true" } else { "" }
        $row = $script:GridTable.NewRow()
        $row["Priority"] = [string]$pattern.Priority
        $row["Code"] = $pattern.Code
        $row["Expression"] = $preview
        $row["Lat=9"] = $forceLat
        $row["Enabled"] = $enabledText
        [void]$script:GridTable.Rows.Add($row)
    }

    # Bind to grid
    $grid.DataSource = $script:GridTable

    # Configure columns after binding
    if ($grid.Columns["Priority"]) { $grid.Columns["Priority"].Width = 40 }
    if ($grid.Columns["Code"]) { $grid.Columns["Code"].Width = 60 }
    if ($grid.Columns["Expression"]) { $grid.Columns["Expression"].AutoSizeMode = 'Fill' }
    if ($grid.Columns["Lat=9"]) { $grid.Columns["Lat=9"].Width = 45 }
    if ($grid.Columns["Enabled"]) { $grid.Columns["Enabled"].Width = 50 }

    $refreshGrid = {
        $script:GridTable.Rows.Clear()
        $validCount = 0
        foreach ($pattern in $script:CurrentPatterns) {
            # Skip patterns without a Code (unless it's {topo})
            if ([string]::IsNullOrWhiteSpace($pattern.Code)) { continue }

            $preview = Get-ExpressionPreview -Expression $pattern.Expression -Logic $pattern.Logic
            $enabledText = if ($pattern.Enabled -eq $false) { "" } else { "true" }
            $forceLat = if ($pattern.ForceLaterality) { "true" } else { "" }
            $row = $script:GridTable.NewRow()
            $row["Priority"] = [string]$pattern.Priority
            $row["Code"] = $pattern.Code
            $row["Expression"] = $preview
            $row["Lat=9"] = $forceLat
            $row["Enabled"] = $enabledText
            [void]$script:GridTable.Rows.Add($row)
            $validCount++
        }
        $lblCount.Text = "Rows: $validCount"
    }

    # Double-click to edit
    $grid.Add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0) { return }

        $pattern = $script:CurrentPatterns[$e.RowIndex]
        $editedPattern = Show-PatternEditDialog -Pattern $pattern -Title "Edit Pattern"
        if ($editedPattern) {
            $script:CurrentPatterns[$e.RowIndex] = $editedPattern
            $script:IsDirty = $true
            & $refreshGrid
            $grid.Rows[$e.RowIndex].Selected = $true
        }
    })

    # Add button handler
    $btnAdd.Add_Click({
        $newPattern = Show-PatternEditDialog -Title "Add Pattern"
        if ($newPattern) {
            $script:CurrentPatterns += $newPattern
            $script:IsDirty = $true
            & $refreshGrid
            $grid.Rows[$grid.Rows.Count - 1].Selected = $true
        }
    })

    # Delete button handler
    $btnDelete.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select a row to delete.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $result = [System.Windows.Forms.MessageBox]::Show("Delete selected pattern?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $idx = $grid.SelectedRows[0].Index
            $newPatterns = @()
            for ($i = 0; $i -lt $script:CurrentPatterns.Count; $i++) {
                if ($i -ne $idx) {
                    $newPatterns += $script:CurrentPatterns[$i]
                }
            }
            $script:CurrentPatterns = $newPatterns
            $script:IsDirty = $true
            & $refreshGrid
        }
    })

    # Move Up handler
    $btnMoveUp.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $idx = $grid.SelectedRows[0].Index
        if ($idx -le 0) { return }

        $temp = $script:CurrentPatterns[$idx]
        $script:CurrentPatterns[$idx] = $script:CurrentPatterns[$idx - 1]
        $script:CurrentPatterns[$idx - 1] = $temp
        $script:IsDirty = $true
        & $refreshGrid
        $grid.Rows[$idx - 1].Selected = $true
    })

    # Move Down handler
    $btnMoveDown.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) { return }
        $idx = $grid.SelectedRows[0].Index
        if ($idx -ge $script:CurrentPatterns.Count - 1) { return }

        $temp = $script:CurrentPatterns[$idx]
        $script:CurrentPatterns[$idx] = $script:CurrentPatterns[$idx + 1]
        $script:CurrentPatterns[$idx + 1] = $temp
        $script:IsDirty = $true
        & $refreshGrid
        $grid.Rows[$idx + 1].Selected = $true
    })

    # Button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(10, 515)
    $buttonPanel.Size = New-Object System.Drawing.Size(860, 40)
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

    # Save handler
    $btnSave.Add_Click({
        try {
            Write-PriorityPatternsFile -Path $filePath -Patterns $script:CurrentPatterns
            $script:IsDirty = $false
            [System.Windows.Forms.MessageBox]::Show("File saved successfully.`n`n$filePath", "Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to save file: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    # Save As handler
    $btnSaveAs.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Title = "Save Priority Patterns As"
        $saveDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($filePath)
        $saveDialog.Filter = "JSONL Files (*.jsonl)|*.jsonl|All Files (*.*)|*.*"
        $saveDialog.DefaultExt = "jsonl"
        $saveDialog.FileName = [System.IO.Path]::GetFileName($filePath)

        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Write-PriorityPatternsFile -Path $saveDialog.FileName -Patterns $script:CurrentPatterns
                $script:IsDirty = $false
                $lblFile.Text = "File: $($saveDialog.FileName)"
                [System.Windows.Forms.MessageBox]::Show("File saved successfully.`n`n$($saveDialog.FileName)", "Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to save file: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
    })

    # Cancel handler
    $btnCancel.Add_Click({
        if ($script:IsDirty) {
            $result = [System.Windows.Forms.MessageBox]::Show("You have unsaved changes. Discard them?", "Unsaved Changes", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        $form.Close()
    })

    # Form closing handler
    $form.Add_FormClosing({
        param($sender, $e)
        if ($script:IsDirty) {
            $result = [System.Windows.Forms.MessageBox]::Show("You have unsaved changes. Discard them?", "Unsaved Changes", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
            }
        }
    })

    $form.Controls.AddRange(@($lblFile, $toolPanel, $grid, $buttonPanel))

    [void]$form.ShowDialog()
}
