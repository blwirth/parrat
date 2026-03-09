# btnAssignUnified.ps1
# Button handler for the unified assignment dialog

function Get-BtnAssignUnifiedHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Unified Assignment")
            return
        }

        if (-not $script:CurrentFilePath) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Unified Assignment")
            return
        }

        try {
            # Count unique patients
            $patientCount = 0
            $processedPatients = @{}
            foreach ($tumor in $script:Tumors) {
                $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)
                if ($patient -ne $null -and -not $processedPatients.ContainsKey($patient)) {
                    $processedPatients[$patient] = $true
                    $patientCount++
                }
            }

            # Show unified options dialog
            $options = Show-UnifiedAssignDialog `
                -FilePath $script:CurrentFilePath `
                -TumorCount $script:Tumors.Count `
                -PatientCount $patientCount `
                -Tumors $script:Tumors `
                -NsMgr $script:NsMgr

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

            # Build options description for logging
            $optionsList = @()
            if ($options.AssignSite) { $optionsList += "Site" }
            if ($options.AssignLaterality) { $optionsList += "Laterality" }
            if ($options.AssignFacility) { $optionsList += "Facility" }
            if ($options.AssignPid) { $optionsList += "PID" }
            $optionsDesc = $optionsList -join ", "
            Write-ParatLog -Level INFO -Message "Starting unified assignment analysis ($optionsDesc) for $($script:Tumors.Count) tumors" -Action "ASSIGN"

            # Measure execution time
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Run combined analysis
            $result = Get-UnifiedAssignments `
                -Tumors $script:Tumors `
                -NsMgr $script:NsMgr `
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
            Write-Host "  - Tumors processed: $($script:Tumors.Count)" -ForegroundColor Cyan
            Write-Host "  - Tumor assignments: $($result.TumorAssignments.Count)" -ForegroundColor Cyan
            Write-Host "  - Patient ID assignments: $($result.PatientAssignments.Count)" -ForegroundColor Cyan

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1}) | Analysis: {2}" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count, $elapsedFormatted

            # Check if any changes found
            $changesFound = ($result.Report | Where-Object { $_.HasChanges }).Count

            if ($changesFound -eq 0) {
                Write-ParatLog -Level INFO -Message "Unified assignment complete: no changes needed" -Action "ASSIGN"
                [System.Windows.Forms.MessageBox]::Show(
                    "No records need updating based on the selected options.",
                    "Unified Assignment",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                Write-ParatLog -Level INFO -Message "Unified assignment analysis complete: $changesFound records with changes" -Action "ASSIGN"
                # Show preview report
                Show-UnifiedPreviewReport `
                    -Report $result.Report `
                    -TumorAssignments $result.TumorAssignments `
                    -PatientAssignments $result.PatientAssignments `
                    -Options $options `
                    -OriginalFilePath $script:CurrentFilePath `
                    -XmlDoc $script:XmlDoc `
                    -Tumors $script:Tumors `
                    -Controls $Controls
            }
        }
        catch {
            Write-ParatError -Message "Unified assignment failed" -Action "ASSIGN" -ErrorRecord $_
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
