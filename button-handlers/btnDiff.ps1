function Get-BtnDiffHandler {
    param(
        [hashtable]$Controls
    )
    
    return {
        try {
            $fileType = $script:FileType
            $recordCount = 0

            if ($fileType -eq 'hl7') {
                $recordCount = $script:Hl7Messages.Count
            }
            else {
                $recordCount = $script:Tumors.Count
            }

            if ($recordCount -eq 0) {
                $typeLabel = if ($fileType -eq 'hl7') { "messages" } else { "tumors" }
                [System.Windows.Forms.MessageBox]::Show("No $typeLabel loaded.", "Diff")
                return
            }

            $rows = $Controls['gridNav'].SelectedRows
            if ($rows.Count -ne 2) {
                [System.Windows.Forms.MessageBox]::Show("Please select exactly two rows in the grid to compare.", "Diff")
                return
            }

            $indexVals = @()
            foreach ($r in $rows) {
                $val = $r.Cells["Index"].Value
                if ($null -ne $val) {
                    $indexVals += ([int]$val)
                }
            }

            if ($indexVals.Count -ne 2) {
                [System.Windows.Forms.MessageBox]::Show("Unable to determine both indices for comparison.", "Diff")
                return
            }

            $idxA = $indexVals[0] - 1
            $idxB = $indexVals[1] - 1

            if ($idxA -lt 0 -or $idxA -ge $recordCount -or
                $idxB -lt 0 -or $idxB -ge $recordCount) {
                [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
                return
            }

            if ($fileType -eq 'hl7') {
                Show-Hl7MessageDiff -IndexA $idxA -IndexB $idxB
            }
            else {
                Show-NaaccrTumorDiff -IndexA $idxA -IndexB $idxB
            }
        }
        catch {
            Write-ParatError -Message "Diff failed" -Action "DIFF" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error during diff: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}
