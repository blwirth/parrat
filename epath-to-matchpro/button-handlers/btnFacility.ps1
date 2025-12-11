function Get-BtnFacilityHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Assign Facility")
            return
        }
        
        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Assign Facility")
            return
        }
        
        try {
            # Try to extract facility number from filename
            $facilityNum = Get-FacilityFromFilename -FilePath $ScriptVars['CurrentFilePath']
            
            # If not found in filename, prompt user
            if (-not $facilityNum) {
                $inputForm = New-Object System.Windows.Forms.Form
                $inputForm.Text = "Enter Facility Number"
                $inputForm.Width = 350
                $inputForm.Height = 170
                $inputForm.StartPosition = "CenterScreen"
                
                $lblPrompt = New-Object System.Windows.Forms.Label
                $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
                $lblPrompt.Size = New-Object System.Drawing.Size(320, 60)
                $lblPrompt.Text = "No 7-digit facility number found in filename.`nPlease enter the facility number (will be padded to 10 digits):"
                
                $txtFacility = New-Object System.Windows.Forms.TextBox
                $txtFacility.Location = New-Object System.Drawing.Point(10, 70)
                $txtFacility.Width = 320
                
                $btnOk = New-Object System.Windows.Forms.Button
                $btnOk.Text = "OK"
                $btnOk.Location = New-Object System.Drawing.Point(150, 100)
                $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
                
                $btnCancel = New-Object System.Windows.Forms.Button
                $btnCancel.Text = "Cancel"
                $btnCancel.Location = New-Object System.Drawing.Point(230, 100)
                $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                
                $inputForm.Controls.AddRange(@($lblPrompt, $txtFacility, $btnOk, $btnCancel))
                $inputForm.AcceptButton = $btnOk
                $inputForm.CancelButton = $btnCancel
                
                $result = $inputForm.ShowDialog()
                
                if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                    $userInput = $txtFacility.Text.Trim()
                    
                    # Validate input is numeric and has reasonable length
                    if ($userInput -match '^\d+$') {
                        $facilityNum = $userInput.PadLeft(10, '0')
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
            
            $Controls['lblStatus'].Text = "Analyzing facilities numbers..."
            $Controls['form'].Refresh()
            
            # Run analysis
            $result = Get-FacilityAssignments -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr'] -FacilityNumber $facilityNum
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
            
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
                    -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -Tumors $ScriptVars['Tumors']
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
