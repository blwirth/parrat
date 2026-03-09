function Get-BtnFacilityHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Assign Facility")
            return
        }

        if (-not $script:CurrentFilePath) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Assign Facility")
            return
        }

        try {
            # Try to extract facility number from filename
            $facilityNum = Get-FacilityFromFilename -FilePath $script:CurrentFilePath

            # Track whether to overwrite existing values
            $overwriteExisting = $false

            # If not found in filename, prompt user
            if (-not $facilityNum) {
                $inputForm = New-Object System.Windows.Forms.Form
                $inputForm.Text = "Enter Facility Number"
                $inputForm.Width = 350
                $inputForm.Height = 200
                $inputForm.StartPosition = "CenterScreen"

                $lblPrompt = New-Object System.Windows.Forms.Label
                $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
                $lblPrompt.Size = New-Object System.Drawing.Size(320, 60)
                $lblPrompt.Text = "No 7-digit facility number found in filename.`nPlease enter the facility number (will be padded to 10 digits):"

                $txtFacility = New-Object System.Windows.Forms.TextBox
                $txtFacility.Location = New-Object System.Drawing.Point(10, 70)
                $txtFacility.Width = 320

                $chkOverwrite = New-Object System.Windows.Forms.CheckBox
                $chkOverwrite.Location = New-Object System.Drawing.Point(10, 100)
                $chkOverwrite.Size = New-Object System.Drawing.Size(320, 30)
                $chkOverwrite.Text = "Overwrite existing reportingFacility values"
                $chkOverwrite.ForeColor = [System.Drawing.Color]::Red
                $chkOverwrite.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

                $btnOk = New-Object System.Windows.Forms.Button
                $btnOk.Text = "OK"
                $btnOk.Location = New-Object System.Drawing.Point(150, 130)
                $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

                $btnCancel = New-Object System.Windows.Forms.Button
                $btnCancel.Text = "Cancel"
                $btnCancel.Location = New-Object System.Drawing.Point(230, 130)
                $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

                $inputForm.Controls.AddRange(@($lblPrompt, $txtFacility, $chkOverwrite, $btnOk, $btnCancel))
                $inputForm.AcceptButton = $btnOk
                $inputForm.CancelButton = $btnCancel

                $result = $inputForm.ShowDialog()

                if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                    $userInput = $txtFacility.Text.Trim()

                    # Validate input is numeric and has reasonable length
                    if ($userInput -match '^\d+$') {
                        $facilityNum = $userInput.PadLeft(10, '0')
                        $overwriteExisting = $chkOverwrite.Checked
                    }
                    else {
                        [System.Windows.Forms.MessageBox]::Show(
                            "Invalid facility number. Must be numeric.",
                            "Error",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Error
                        )
                        return
                    }
                }
                else {
                    # User cancelled
                    return
                }
            }
            else {
                # Facility found in filename - show dialog with overwrite option
                $confirmForm = New-Object System.Windows.Forms.Form
                $confirmForm.Text = "Confirm Facility Assignment"
                $confirmForm.Width = 400
                $confirmForm.Height = 200
                $confirmForm.StartPosition = "CenterScreen"

                $lblConfirm = New-Object System.Windows.Forms.Label
                $lblConfirm.Location = New-Object System.Drawing.Point(10, 10)
                $lblConfirm.Size = New-Object System.Drawing.Size(370, 60)
                $lblConfirm.Text = "Facility number found in filename: $facilityNum`nProceed with assignment?"

                $chkOverwrite = New-Object System.Windows.Forms.CheckBox
                $chkOverwrite.Location = New-Object System.Drawing.Point(10, 70)
                $chkOverwrite.Size = New-Object System.Drawing.Size(370, 30)
                $chkOverwrite.Text = "Overwrite existing reportingFacility values"
                $chkOverwrite.ForeColor = [System.Drawing.Color]::Red
                $chkOverwrite.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

                $btnOk = New-Object System.Windows.Forms.Button
                $btnOk.Text = "OK"
                $btnOk.Location = New-Object System.Drawing.Point(200, 110)
                $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

                $btnCancel = New-Object System.Windows.Forms.Button
                $btnCancel.Text = "Cancel"
                $btnCancel.Location = New-Object System.Drawing.Point(280, 110)
                $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

                $confirmForm.Controls.AddRange(@($lblConfirm, $chkOverwrite, $btnOk, $btnCancel))
                $confirmForm.AcceptButton = $btnOk
                $confirmForm.CancelButton = $btnCancel

                $result = $confirmForm.ShowDialog()

                if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                    $overwriteExisting = $chkOverwrite.Checked
                }
                else {
                    # User cancelled
                    return
                }
            }

            $Controls['lblStatus'].Text = "Analyzing facilities numbers..."
            $Controls['form'].Refresh()

            # Run analysis
            $result = Get-FacilityAssignments -Tumors $script:Tumors -NsMgr $script:NsMgr -FacilityNumber $facilityNum -OverwriteExisting $overwriteExisting

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count

            if ($result.Report.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "All tumors already have valid facility numbers!",
                    "Assignment complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                # Show preview report
                Show-FacilityAssignmentReport `
                    -Report $result.Report `
                    -Assignments $result.Assignments `
                    -FacilityNumber $facilityNum `
                    -OriginalFilePath $script:CurrentFilePath `
                    -XmlDoc $script:XmlDoc `
                    -Tumors $script:Tumors `
                    -OverwriteExisting $overwriteExisting
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error during facility assignment: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error during facility assignment"
        }
    }
}

