function Get-BtnAddPidHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Add Patient ID")
            return
        }

        if (-not $script:CurrentFilePath) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Add Patient ID")
            return
        }

        try {
            $Controls['lblStatus'].Text = "Analyzing patients..."
            $Controls['form'].Refresh()

            # First, check if all patients already have IDs
            $processedPatients = @{}
            $allHaveIds = $true

            for ($i = 0; $i -lt $script:Tumors.Count; $i++) {
                $tumor = $script:Tumors[$i]
                $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

                if ($null -eq $patient) { continue }

                if (-not $processedPatients.ContainsKey($patient)) {
                    $processedPatients[$patient] = $true

                    $idNode = $patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $script:NsMgr)
                    $currentId = if ($idNode) { $idNode.InnerText } else { "" }

                    if ([string]::IsNullOrWhiteSpace($currentId)) {
                        $allHaveIds = $false
                        break
                    }
                }
            }

            $mode = "Default"

            # If all patients have IDs, show options dialog
            if ($allHaveIds) {
                $optionForm = New-Object System.Windows.Forms.Form
                $optionForm.Text = "All Patients Have IDs"
                $optionForm.Width = 500
                $optionForm.Height = 275
                $optionForm.StartPosition = "CenterScreen"
                $optionForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
                $optionForm.MaximizeBox = $false
                $optionForm.MinimizeBox = $false

                $lblPrompt = New-Object System.Windows.Forms.Label
                $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
                $lblPrompt.Size = New-Object System.Drawing.Size(460, 80)
                $lblPrompt.Text = "All patients already have patientIdNumber assigned.`n`nWhat would you like to do?"
                $optionForm.Controls.Add($lblPrompt)

                $btnOverwriteAll = New-Object System.Windows.Forms.Button
                $btnOverwriteAll.Text = "1. Overwrite All (Starting at 00000001)"
                $btnOverwriteAll.Location = New-Object System.Drawing.Point(10, 100)
                $btnOverwriteAll.Size = New-Object System.Drawing.Size(460, 40)
                $btnOverwriteAll.DialogResult = [System.Windows.Forms.DialogResult]::Yes
                $optionForm.Controls.Add($btnOverwriteAll)

                $btnReplaceZeros = New-Object System.Windows.Forms.Button
                $btnReplaceZeros.Text = "2. Replace Zero IDs Only (Starting at 90000001)"
                $btnReplaceZeros.Location = New-Object System.Drawing.Point(10, 150)
                $btnReplaceZeros.Size = New-Object System.Drawing.Size(460, 40)
                $btnReplaceZeros.DialogResult = [System.Windows.Forms.DialogResult]::No
                $optionForm.Controls.Add($btnReplaceZeros)

                $btnCancel = New-Object System.Windows.Forms.Button
                $btnCancel.Text = "Cancel"
                $btnCancel.Location = New-Object System.Drawing.Point(380, 200)
                $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
                $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $optionForm.CancelButton = $btnCancel
                $optionForm.Controls.Add($btnCancel)

                $result = $optionForm.ShowDialog()

                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $mode = "OverwriteAll"
                }
                elseif ($result -eq [System.Windows.Forms.DialogResult]::No) {
                    $mode = "ReplaceZeros"
                }
                else {
                    # User cancelled
                    $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count
                    return
                }
            }

            # Run analysis with selected mode
            $result = Get-PatientIdAssignments -Tumors $script:Tumors -NsMgr $script:NsMgr -Mode $mode

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count

            if ($result.Report.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No patients need patientIdNumber assignment!",
                    "Assignment complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                # Show preview report
                Show-PatientIdReport `
                    -Report $result.Report `
                    -Assignments $result.Assignments `
                    -OriginalFilePath $script:CurrentFilePath `
                    -XmlDoc $script:XmlDoc `
                    -Tumors $script:Tumors
            }
        }
        catch {
            Write-ParatError -Message "Add Patient ID failed" -Action "MODIFY_XML" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error during analysis: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error during analysis"
        }
    }
}

