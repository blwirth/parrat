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
            
            # Run analysis
            $result = Get-MissingFields -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr']
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
            
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
