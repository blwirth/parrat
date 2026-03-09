function Show-VariableSelectionDialog {
    <#
    .SYNOPSIS
        Shows a dual-list shuttle dialog for selecting NAACCR variables to remove.
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
    $dlg.Size = New-Object System.Drawing.Size(900, 520)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimumSize = New-Object System.Drawing.Size(600, 350)

    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Location = New-Object System.Drawing.Point(12, 12)
    $txtFilter.Size = New-Object System.Drawing.Size(390, 23)
    $txtFilter.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Placeholder text — set ForeColor before Text to avoid TextChanged race
    $placeholderText = "Search variables..."
    $txtFilter.ForeColor = [System.Drawing.Color]::Gray
    $txtFilter.Text = $placeholderText
    $txtFilter.Add_GotFocus({
        if ($txtFilter.ForeColor -eq [System.Drawing.Color]::Gray) {
            $txtFilter.ForeColor = [System.Drawing.Color]::Black
            $txtFilter.Text = ""
        }
    })
    $txtFilter.Add_LostFocus({
        if ([string]::IsNullOrEmpty($txtFilter.Text)) {
            $txtFilter.ForeColor = [System.Drawing.Color]::Gray
            $txtFilter.Text = $placeholderText
        }
    })

    $lblAvailable = New-Object System.Windows.Forms.Label
    $lblAvailable.Location = New-Object System.Drawing.Point(12, 40)
    $lblAvailable.Size = New-Object System.Drawing.Size(390, 18)
    $lblAvailable.ForeColor = [System.Drawing.Color]::Gray
    $lblAvailable.Text = "$($Variables.Count) of $($Variables.Count) variables"

    $lblRemove = New-Object System.Windows.Forms.Label
    $lblRemove.Location = New-Object System.Drawing.Point(460, 40)
    $lblRemove.Size = New-Object System.Drawing.Size(390, 18)
    $lblRemove.ForeColor = [System.Drawing.Color]::Gray
    $lblRemove.Text = "Variables to Remove (0)"

    $listAll = New-Object System.Windows.Forms.ListBox
    $listAll.Location = New-Object System.Drawing.Point(12, 60)
    $listAll.Size = New-Object System.Drawing.Size(390, 370)
    $listAll.Font = New-Object System.Drawing.Font("Consolas", 9)
    $listAll.IntegralHeight = $false
    $listAll.SelectionMode = 'MultiExtended'

    $listRemoveBox = New-Object System.Windows.Forms.ListBox
    $listRemoveBox.Location = New-Object System.Drawing.Point(460, 60)
    $listRemoveBox.Size = New-Object System.Drawing.Size(390, 370)
    $listRemoveBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $listRemoveBox.IntegralHeight = $false
    $listRemoveBox.SelectionMode = 'MultiExtended'

    # --- Build display items and populate left list ---
    # DisplayName comes from the NAACCR dictionary (data/dictionaries/naaccr-items-v25.json)
    # via Get-NaaccrItemByXmlId in Get-UniqueNaaccrIds; custom items show "(custom)" suffix
    $allItems = @()
    foreach ($v in $Variables) {
        $displayText = "$($v.XmlId)) - $($v.Count) [$($v.Levels)]"
        $allItems += [PSCustomObject]@{
            DisplayText = $displayText
            XmlId       = $v.XmlId
        }
        [void]$listAll.Items.Add($displayText)
    }

    # HashSet to track which IDs are in the remove list (reference type, shared across handlers)
    $removeSet = New-Object 'System.Collections.Generic.HashSet[string]'

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = [char]0x25B6  # right-pointing triangle
    $btnAdd.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnAdd.Size = New-Object System.Drawing.Size(40, 30)
    $btnAdd.Location = New-Object System.Drawing.Point(410, 200)
    $btnAdd.Enabled = $false

    $btnRemoveFromList = New-Object System.Windows.Forms.Button
    $btnRemoveFromList.Text = [char]0x25C0  # left-pointing triangle
    $btnRemoveFromList.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnRemoveFromList.Size = New-Object System.Drawing.Size(40, 30)
    $btnRemoveFromList.Location = New-Object System.Drawing.Point(410, 240)
    $btnRemoveFromList.Enabled = $false

    $btnConfirm = New-Object System.Windows.Forms.Button
    $btnConfirm.Text = "Remove"
    $btnConfirm.Size = New-Object System.Drawing.Size(80, 28)
    $btnConfirm.Location = New-Object System.Drawing.Point(686, 442)
    $btnConfirm.Enabled = $false

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(80, 28)
    $btnCancel.Location = New-Object System.Drawing.Point(772, 442)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $btnCancel

    # --- Proportional layout applied on Shown + Resize ---
    # Shown fires after the form has its final dimensions; Resize keeps it updated
    $layoutHandler = {
        $cw = $dlg.ClientSize.Width
        $ch = $dlg.ClientSize.Height
        if ($cw -lt 100 -or $ch -lt 100) { return }
        $margin = 12
        $arrowW = 40
        $gap = 8
        $topY = 60
        $bottomH = 48

        $listW = [int](($cw - (2 * $margin) - $arrowW - (2 * $gap)) / 2)
        $arrowX = $margin + $listW + $gap
        $rightX = $arrowX + $arrowW + $gap
        $listH = $ch - $topY - $bottomH

        $txtFilter.Width = $listW
        $lblAvailable.Width = $listW
        $listAll.Width = $listW
        $listAll.Height = $listH

        $centerY = $topY + [int]($listH / 2)
        $btnAdd.Left = $arrowX
        $btnAdd.Top = $centerY - 35
        $btnRemoveFromList.Left = $arrowX
        $btnRemoveFromList.Top = $centerY + 5

        $lblRemove.Left = $rightX
        $lblRemove.Width = $listW
        $listRemoveBox.Left = $rightX
        $listRemoveBox.Width = $listW
        $listRemoveBox.Height = $listH

        $btnConfirm.Left = $cw - $margin - 80 - 6 - 80
        $btnConfirm.Top = $ch - $margin - 28
        $btnCancel.Left = $cw - $margin - 80
        $btnCancel.Top = $ch - $margin - 28
    }

    $dlg.Add_Shown({ & $layoutHandler })
    $dlg.Add_Resize({ & $layoutHandler })

    $btnAdd.Add_Click({
        $toMove = @($listAll.SelectedItems)
        $listAll.BeginUpdate()
        foreach ($selText in $toMove) {
            $match = $allItems | Where-Object { $_.DisplayText -eq $selText } | Select-Object -First 1
            if ($null -ne $match -and -not $removeSet.Contains($match.XmlId)) {
                [void]$removeSet.Add($match.XmlId)
                [void]$listRemoveBox.Items.Add($selText)
                $listAll.Items.Remove($selText)
            }
        }
        $listAll.EndUpdate()
        $lblAvailable.Text = "$($listAll.Items.Count) of $($Variables.Count) variables"
        $lblRemove.Text = "Variables to Remove ($($listRemoveBox.Items.Count))"
        $btnConfirm.Enabled = ($listRemoveBox.Items.Count -gt 0)
    })

    $btnRemoveFromList.Add_Click({
        $toRemove = @($listRemoveBox.SelectedItems)
        $filterLower = if ($txtFilter.ForeColor -eq [System.Drawing.Color]::Gray) { "" } else { $txtFilter.Text.ToLower() }
        $listAll.BeginUpdate()
        foreach ($selText in $toRemove) {
            $match = $allItems | Where-Object { $_.DisplayText -eq $selText } | Select-Object -First 1
            if ($null -ne $match) {
                [void]$removeSet.Remove($match.XmlId)
                if ([string]::IsNullOrEmpty($filterLower) -or $match.DisplayText.ToLower().Contains($filterLower)) {
                    [void]$listAll.Items.Add($selText)
                }
            }
            $listRemoveBox.Items.Remove($selText)
        }
        $listAll.EndUpdate()
        $lblAvailable.Text = "$($listAll.Items.Count) of $($Variables.Count) variables"
        $lblRemove.Text = "Variables to Remove ($($listRemoveBox.Items.Count))"
        $btnConfirm.Enabled = ($listRemoveBox.Items.Count -gt 0)
    })

    $listAll.Add_SelectedIndexChanged({
        $btnAdd.Enabled = ($listAll.SelectedItems.Count -gt 0)
    })
    $listRemoveBox.Add_SelectedIndexChanged({
        $btnRemoveFromList.Enabled = ($listRemoveBox.SelectedItems.Count -gt 0)
    })

    $listAll.Add_DoubleClick({
        if ($listAll.SelectedItems.Count -gt 0) { $btnAdd.PerformClick() }
    })
    $listRemoveBox.Add_DoubleClick({
        if ($listRemoveBox.SelectedItems.Count -gt 0) { $btnRemoveFromList.PerformClick() }
    })

    $txtFilter.Add_TextChanged({
        if ($txtFilter.ForeColor -eq [System.Drawing.Color]::Gray) { return }
        $filterLower = $txtFilter.Text.ToLower()

        $listAll.BeginUpdate()
        $listAll.Items.Clear()
        $matchCount = 0
        foreach ($item in $allItems) {
            if ($removeSet.Contains($item.XmlId)) { continue }
            if ([string]::IsNullOrEmpty($filterLower) -or $item.DisplayText.ToLower().Contains($filterLower)) {
                [void]$listAll.Items.Add($item.DisplayText)
                $matchCount++
            }
        }
        $listAll.EndUpdate()
        $lblAvailable.Text = "$matchCount of $($Variables.Count) variables"
    })

    $btnConfirm.Add_Click({
        $selectedIds = @()
        foreach ($selText in $listRemoveBox.Items) {
            $match = $allItems | Where-Object { $_.DisplayText -eq $selText } | Select-Object -First 1
            if ($null -ne $match) { $selectedIds += $match.XmlId }
        }
        if ($selectedIds.Count -gt 0) {
            $dlg.Tag = $selectedIds
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })

    $dlg.Controls.AddRange(@(
        $txtFilter, $lblAvailable, $lblRemove,
        $listAll, $btnAdd, $btnRemoveFromList, $listRemoveBox,
        $btnConfirm, $btnCancel
    ))

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
        [hashtable]$Controls
    )

    return {
        if ($null -eq $script:XmlDoc) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Remove Variable")
            return
        }

        if ($null -eq $script:Tumors -or $script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No records found in the loaded file.", "Remove Variable")
            return
        }

        if (-not $script:CurrentFilePath) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Remove Variable")
            return
        }

        try {
            $Controls['lblStatus'].Text = "Scanning variables..."
            $Controls['form'].Refresh()

            $variables = Get-UniqueNaaccrIds -XmlDoc $script:XmlDoc -NsMgr $script:NsMgr

            if ($null -eq $variables -or @($variables).Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No variables found in the loaded file.", "Remove Variable")
                $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
                return
            }

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count

            $selectedIds = Show-VariableSelectionDialog -Variables @($variables)

            if ($null -eq $selectedIds -or @($selectedIds).Count -eq 0) {
                return
            }
            $selectedIds = @($selectedIds)

            $totalOccurrences = 0
            $confirmLines = @()
            foreach ($id in $selectedIds) {
                $varInfo = @($variables) | Where-Object { $_.XmlId -eq $id } | Select-Object -First 1
                if ($null -ne $varInfo) {
                    $totalOccurrences += $varInfo.Count
                    $confirmLines += "  $id - $($varInfo.Count) occurrences [$($varInfo.Levels)]"
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

            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($script:CurrentFilePath)
            $extension = [System.IO.Path]::GetExtension($script:CurrentFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($script:CurrentFilePath)
            $suffix = "$($selectedIds.Count)v"

            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-rm$suffix$extension")

            $idsJoined = $selectedIds -join ', '
            Write-ParatLog -Level INFO -Message "Removing $($selectedIds.Count) $varWord ($idsJoined) totaling $totalOccurrences occurrences from $([System.IO.Path]::GetFileName($script:CurrentFilePath))" -Action "MODIFY_XML"

            $result = Remove-XmlVariable -XmlDoc $script:XmlDoc -NaaccrIds $selectedIds -OutputPath $outputPath

            $outputFileName = [System.IO.Path]::GetFileName($outputPath)
            Write-ParatLog -Level INFO -Message "Remove Variable: removed $($result.RemovedCount) occurrences of $($selectedIds.Count) $varWord, saved to $outputFileName" -Action "MODIFY_XML"

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count

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
