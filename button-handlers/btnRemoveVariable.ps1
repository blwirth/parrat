function Show-VariableSelectionDialog {
    <#
    .SYNOPSIS
        Shows a searchable list of NAACCR variables for the user to select.
    .PARAMETER Variables
        Array of PSCustomObject from Get-UniqueNaaccrIds.
    .RETURNS
        Array of XmlId strings for the selected variables, or $null if cancelled.
    #>
    param(
        [array]$Variables
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Select Variables to Remove"
    $dlg.Size = New-Object System.Drawing.Size(600, 500)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimumSize = New-Object System.Drawing.Size(400, 300)

    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Location = New-Object System.Drawing.Point(12, 12)
    $txtFilter.Size = New-Object System.Drawing.Size(560, 23)
    $txtFilter.Anchor = 'Top,Left,Right'
    $txtFilter.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Placeholder text via a flag to avoid race conditions
    $placeholderText = "Search variables..."
    $placeholderActive = $true
    $txtFilter.Text = $placeholderText
    $txtFilter.ForeColor = [System.Drawing.Color]::Gray
    $txtFilter.Add_GotFocus({
        if ($placeholderActive) {
            $placeholderActive = $false
            $txtFilter.ForeColor = [System.Drawing.Color]::Black
            $txtFilter.Text = ""
        }
    })
    $txtFilter.Add_LostFocus({
        if ([string]::IsNullOrEmpty($txtFilter.Text)) {
            $placeholderActive = $true
            $txtFilter.ForeColor = [System.Drawing.Color]::Gray
            $txtFilter.Text = $placeholderText
        }
    })

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(12, 40)
    $lblCount.Size = New-Object System.Drawing.Size(560, 18)
    $lblCount.Anchor = 'Top,Left,Right'
    $lblCount.ForeColor = [System.Drawing.Color]::Gray
    $lblCount.Text = "$($Variables.Count) of $($Variables.Count) variables"

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(12, 62)
    $listBox.Size = New-Object System.Drawing.Size(560, 350)
    $listBox.Anchor = 'Top,Bottom,Left,Right'
    $listBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $listBox.IntegralHeight = $false
    $listBox.SelectionMode = 'MultiExtended'

    # Build display items and populate list
    $allItems = @()
    foreach ($v in $Variables) {
        $displayText = "$($v.DisplayName) ($($v.XmlId)) - $($v.Count) occurrences [$($v.Levels)]"
        $allItems += [PSCustomObject]@{
            DisplayText = $displayText
            XmlId       = $v.XmlId
        }
        [void]$listBox.Items.Add($displayText)
    }

    # Filter logic
    $txtFilter.Add_TextChanged({
        if ($placeholderActive) { return }
        $filterLower = $txtFilter.Text.ToLower()

        $listBox.BeginUpdate()
        $listBox.Items.Clear()
        $matchCount = 0
        foreach ($item in $allItems) {
            if ([string]::IsNullOrEmpty($filterLower) -or $item.DisplayText.ToLower().Contains($filterLower)) {
                [void]$listBox.Items.Add($item.DisplayText)
                $matchCount++
            }
        }
        $listBox.EndUpdate()
        $lblCount.Text = "$matchCount of $($Variables.Count) variables"
    })

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove"
    $btnRemove.Size = New-Object System.Drawing.Size(80, 28)
    $btnRemove.Location = New-Object System.Drawing.Point(408, 422)
    $btnRemove.Anchor = 'Bottom,Right'
    $btnRemove.Enabled = $false
    $btnRemove.Add_Click({
        $selectedIds = @()
        foreach ($selText in $listBox.SelectedItems) {
            $match = $allItems | Where-Object { $_.DisplayText -eq $selText } | Select-Object -First 1
            if ($null -ne $match) {
                $selectedIds += $match.XmlId
            }
        }
        if ($selectedIds.Count -gt 0) {
            $dlg.Tag = $selectedIds
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(80, 28)
    $btnCancel.Location = New-Object System.Drawing.Point(494, 422)
    $btnCancel.Anchor = 'Bottom,Right'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $btnCancel

    # Enable Remove button when selection changes
    $listBox.Add_SelectedIndexChanged({
        $btnRemove.Enabled = ($listBox.SelectedItems.Count -gt 0)
    })

    # Double-click confirms selection
    $listBox.Add_DoubleClick({
        if ($listBox.SelectedItems.Count -gt 0) {
            $btnRemove.PerformClick()
        }
    })

    $dlg.Controls.AddRange(@($txtFilter, $lblCount, $listBox, $btnRemove, $btnCancel))

    $result = $dlg.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $returnVal = $dlg.Tag
        $dlg.Dispose()
        return $returnVal
    }

    $dlg.Dispose()
    return $null
}

function Get-BtnRemoveVariableHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        # Validate XML file is loaded
        if ($null -eq $ScriptVars['XmlDoc']) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Remove Variable")
            return
        }

        if ($null -eq $ScriptVars['Tumors'] -or $ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No records found in the loaded file.", "Remove Variable")
            return
        }

        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Remove Variable")
            return
        }

        try {
            $Controls['lblStatus'].Text = "Scanning variables..."
            $Controls['form'].Refresh()

            # Scan for all unique variables
            $variables = Get-UniqueNaaccrIds -XmlDoc $ScriptVars['XmlDoc'] -NsMgr $ScriptVars['NsMgr']

            if ($null -eq $variables -or @($variables).Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No variables found in the loaded file.", "Remove Variable")
                $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
                return
            }

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count

            # Show selection dialog (returns array of XmlId strings)
            $selectedIds = Show-VariableSelectionDialog -Variables @($variables)

            if ($null -eq $selectedIds -or @($selectedIds).Count -eq 0) {
                return
            }
            $selectedIds = @($selectedIds)

            # Build confirmation details for all selected variables
            $totalOccurrences = 0
            $confirmLines = @()
            foreach ($id in $selectedIds) {
                $varInfo = @($variables) | Where-Object { $_.XmlId -eq $id } | Select-Object -First 1
                if ($null -ne $varInfo) {
                    $totalOccurrences += $varInfo.Count
                    $confirmLines += "  $($varInfo.DisplayName) ($id) - $($varInfo.Count) occurrences [$($varInfo.Levels)]"
                }
            }

            $varWord = if ($selectedIds.Count -eq 1) { "variable" } else { "variables" }
            $confirmMessage = "Remove all occurrences of $($selectedIds.Count) $($varWord)?`n`n" +
                ($confirmLines -join "`n") +
                "`n`nTotal occurrences to remove: $totalOccurrences`n`nA new file will be created. The original file will not be modified."

            $confirmResult = [System.Windows.Forms.MessageBox]::Show(
                $confirmMessage,
                "Confirm Remove Variable",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            $Controls['lblStatus'].Text = "Removing $($selectedIds.Count) $varWord..."
            $Controls['form'].Refresh()

            # Build output path with suffix based on selection count
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptVars['CurrentFilePath'])
            $extension = [System.IO.Path]::GetExtension($ScriptVars['CurrentFilePath'])
            $directory = [System.IO.Path]::GetDirectoryName($ScriptVars['CurrentFilePath'])
            if ($selectedIds.Count -le 3) {
                $suffix = ($selectedIds -join '-')
            } else {
                $suffix = "$($selectedIds.Count)vars"
            }
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-removed-$suffix$extension")

            $idsJoined = $selectedIds -join ', '
            Write-ParatLog -Level INFO -Message "Removing $($selectedIds.Count) $varWord ($idsJoined) totaling $totalOccurrences occurrences from $([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath']))" -Action "MODIFY_XML"

            # Remove the variables
            $result = Remove-XmlVariable -XmlDoc $ScriptVars['XmlDoc'] -NaaccrIds $selectedIds -OutputPath $outputPath

            $outputFileName = [System.IO.Path]::GetFileName($outputPath)
            Write-ParatLog -Level INFO -Message "Remove Variable: removed $($result.RemovedCount) occurrences of $($selectedIds.Count) $varWord, saved to $outputFileName" -Action "MODIFY_XML"

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count

            $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                "Removed $($result.RemovedCount) total occurrences of $($selectedIds.Count) $($varWord).`n`nSaved to:`n$outputPath`n`nOpen containing folder?",
                "Remove Variable Complete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Process "explorer.exe" -ArgumentList "/select,`"$outputPath`""
            }
        }
        catch {
            Write-ParatError -Message "Remove Variable failed" -Action "MODIFY_XML" -ErrorRecord $_
            Show-CopyableErrorDialog -Message "Error removing variable" -Details $_.Exception.ToString() -Title "Remove Variable Error"
            $Controls['lblStatus'].Text = "Error removing variable"
        }
    }
}
