function Get-BtnDedupPrimaryKeyHandler {
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
            $Controls['lblStatus'].Text = "Analyzing duplicates by primary key..."
            $Controls['form'].Refresh()
            
            # Run dedup analysis by primary key
            $result = Get-DuplicatesByPrimaryKey -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr']
            
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count
            
            # Show preview modal before deduping
            Show-DeduplicationPreview `
                -Result $result `
                -OriginalCount $ScriptVars['Tumors'].Count `
                -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                -XmlDoc $ScriptVars['XmlDoc'] `
                -Tumors $ScriptVars['Tumors'] `
                -NsMgr $ScriptVars['NsMgr'] `
                -DedupType "PrimaryKey"
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



