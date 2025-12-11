function Get-BtnDiffHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['Tumors'].Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Diff")
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

        if ($idxA -lt 0 -or $idxA -ge $ScriptVars['Tumors'].Count -or
            $idxB -lt 0 -or $idxB -ge $ScriptVars['Tumors'].Count) {
            [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
            return
        }

        Show-NaaccrTumorDiff -IndexA $idxA -IndexB $idxB
    }
}
