function Get-BtnAssignHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Assign Site/Lat")
            return
        }
        
        try {
            $Controls['lblStatus'].Text = "Analyzing missing fields..."
            $Controls['form'].Refresh()
            
            # Measure execution time
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Run analysis
            $result = Get-MissingFields -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr']
            
            $stopwatch.Stop()
            $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
            $elapsedFormatted = if ($elapsedSeconds -lt 60) {
                "{0:F2} seconds" -f $elapsedSeconds
            } else {
                $minutes = [math]::Floor($elapsedSeconds / 60)
                $seconds = $elapsedSeconds % 60
                "{0} minute(s) {1:F2} seconds" -f $minutes, $seconds
            }
            
            Write-Host "Analysis completed in $elapsedFormatted" -ForegroundColor Green
            Write-Host "  - Tumors processed: $($ScriptVars['Tumors'].Count)" -ForegroundColor Cyan
            Write-Host "  - Assignments found: $($result.Assignments.Count)" -ForegroundColor Cyan
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1}) | Analysis: {2}" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count, $elapsedFormatted
            
            if ($result.Report.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "All tumors have primarySite and laterality assigned!",
                    "Assignment complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                # Show preview report
                Show-AssignmentReport `
                    -Report $result.Report `
                    -Assignments $result.Assignments `
                    -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -Tumors $ScriptVars['Tumors']
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error during analysis: $($_.Exception.Message)",
                "Error"
            )
            $Controls['lblStatus'].Text = "Error during analysis"
        }
    }
}

