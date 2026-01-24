# btnAssignUnified.ps1
# Button handler for the unified assignment dialog

function Get-BtnAssignUnifiedHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Unified Assignment")
            return
        }

        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Unified Assignment")
            return
        }

        try {
            # Count unique patients
            $patientCount = 0
            $processedPatients = @{}
            foreach ($tumor in $ScriptVars['Tumors']) {
                $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $ScriptVars['NsMgr'])
                if ($patient -ne $null -and -not $processedPatients.ContainsKey($patient)) {
                    $processedPatients[$patient] = $true
                    $patientCount++
                }
            }

            # Show unified options dialog
            $options = Show-UnifiedAssignDialog `
                -FilePath $ScriptVars['CurrentFilePath'] `
                -TumorCount $ScriptVars['Tumors'].Count `
                -PatientCount $patientCount `
                -Tumors $ScriptVars['Tumors'] `
                -NsMgr $ScriptVars['NsMgr']

            if ($null -eq $options) {
                # User cancelled
                return
            }

            # Check if at least one option is selected
            if (-not $options.AssignSite -and -not $options.AssignLaterality -and
                -not $options.AssignFacility -and -not $options.AssignPid) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Please select at least one assignment option.",
                    "Unified Assignment",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }

            $Controls['lblStatus'].Text = "Analyzing records for unified assignment..."
            $Controls['form'].Refresh()

            # Measure execution time
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Run combined analysis
            $result = Get-UnifiedAssignments `
                -Tumors $ScriptVars['Tumors'] `
                -NsMgr $ScriptVars['NsMgr'] `
                -Options $options

            $stopwatch.Stop()
            $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
            $elapsedFormatted = if ($elapsedSeconds -lt 60) {
                "{0:F2} seconds" -f $elapsedSeconds
            }
            else {
                $minutes = [math]::Floor($elapsedSeconds / 60)
                $seconds = $elapsedSeconds % 60
                "{0} minute(s) {1:F2} seconds" -f $minutes, $seconds
            }

            Write-Host "Analysis completed in $elapsedFormatted" -ForegroundColor Green
            Write-Host "  - Tumors processed: $($ScriptVars['Tumors'].Count)" -ForegroundColor Cyan
            Write-Host "  - Tumor assignments: $($result.TumorAssignments.Count)" -ForegroundColor Cyan
            Write-Host "  - Patient ID assignments: $($result.PatientAssignments.Count)" -ForegroundColor Cyan

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1}) | Analysis: {2}" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count, $elapsedFormatted

            # Check if any changes found
            $changesFound = ($result.Report | Where-Object { $_.HasChanges }).Count

            if ($changesFound -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No records need updating based on the selected options.",
                    "Unified Assignment",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                # Show preview report
                Show-UnifiedPreviewReport `
                    -Report $result.Report `
                    -TumorAssignments $result.TumorAssignments `
                    -PatientAssignments $result.PatientAssignments `
                    -Options $options `
                    -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -Tumors $ScriptVars['Tumors']
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error during unified assignment: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error during unified assignment"
        }
    }
}
