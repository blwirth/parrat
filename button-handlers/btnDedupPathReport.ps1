function Get-BtnDedupPathReportHandler {
    param(
        [hashtable]$Controls
    )

    return {
        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No XML file loaded.", "Deduplicate")
            return
        }

        if (-not $script:CurrentFilePath) {
            [System.Windows.Forms.MessageBox]::Show("No file path available.", "Deduplicate")
            return
        }

        try {
            $Controls['lblStatus'].Text = "Analyzing duplicates by pathReportNumber1..."
            $Controls['form'].Refresh()

            Write-ParatLog -Level INFO -Message "Starting deduplication (pathReportNumber1) for $($script:Tumors.Count) tumors" -Action "DEDUPLICATE"

            # Run dedup analysis by pathReportNumber1
            $result = Get-DuplicatesByPathReport -Tumors $script:Tumors -NsMgr $script:NsMgr

            Write-ParatLog -Level INFO -Message "Deduplication analysis complete: $($result.DuplicateCount) duplicates found" -Action "DEDUPLICATE"

            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f ([System.IO.Path]::GetFileName($script:CurrentFilePath)), $script:Tumors.Count

            # Show preview modal before deduping
            Show-DeduplicationPreview `
                -Result $result `
                -OriginalCount $script:Tumors.Count `
                -OriginalFilePath $script:CurrentFilePath `
                -XmlDoc $script:XmlDoc `
                -Tumors $script:Tumors `
                -NsMgr $script:NsMgr `
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
