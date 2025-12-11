function Get-BtnDedupHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Deduplicate")
            return
        }
        
        if (-not $ScriptVars['CurrentFilePath']) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Deduplicate")
            return
        }
        
        try {
            $Controls['lblStatus'].Text = "Analyzing duplicates..."
            $Controls['form'].Refresh()
            
            # Run dedup analysis
            $result = Get-Duplicates -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr']
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
            
            if ($result.Report.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No duplicates found!",
                    "Deduplication complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                # Show Report
                Show-DeduplicationReport `
                    -Report $result.Report `
                    -IndicesToKeep $result.IndicesToKeep `
                    -OriginalCount $ScriptVars['Tumors'].Count `
                    -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                    -XmlDoc $ScriptVars['XmlDoc'] `
                    -Tumors $ScriptVars['Tumors']
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Error during deduplication: $($_.Exception.Message)",
                "Error", 
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error during deduplication"
        }
    }
}
