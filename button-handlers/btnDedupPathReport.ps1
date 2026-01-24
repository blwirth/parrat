function Get-BtnDedupPathReportHandler {
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
            $Controls['lblStatus'].Text = "Analyzing duplicates by pathReportNumber1..."
            $Controls['form'].Refresh()

            Write-ParatLog -Level INFO -Message "Starting deduplication (pathReportNumber1) for $($ScriptVars['Tumors'].Count) tumors" -Action "DEDUPLICATE"

            # Run dedup analysis by pathReportNumber1
            $result = Get-DuplicatesByPathReport -Tumors $ScriptVars['Tumors'] -NsMgr $ScriptVars['NsMgr']

            Write-ParatLog -Level INFO -Message "Deduplication analysis complete: $($result.DuplicateCount) duplicates found" -Action "DEDUPLICATE"

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($ScriptVars['CurrentFilePath'])), $ScriptVars['Tumors'].Count

            # Show preview modal before deduping
            Show-DeduplicationPreview `
                -Result $result `
                -OriginalCount $ScriptVars['Tumors'].Count `
                -OriginalFilePath $ScriptVars['CurrentFilePath'] `
                -XmlDoc $ScriptVars['XmlDoc'] `
                -Tumors $ScriptVars['Tumors'] `
                -NsMgr $ScriptVars['NsMgr'] `
                -DedupType "PathReport"
        }
        catch {
            Write-ParatError -Message "Deduplication (pathReportNumber1) failed" -Action "DEDUPLICATE" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show("Error during deduplication: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $Controls['lblStatus'].Text = "Error during deduplication"
        }
    }
}

