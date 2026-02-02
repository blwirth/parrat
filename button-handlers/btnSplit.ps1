# btnSplit.ps1
# Button handler for Split functionality

function Get-BtnSplitHandler {
    return {
        try {
            Start-SplitFile
        }
        catch {
            Write-ParatError -Message "Split file failed" -Action "SPLIT" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error during file split: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}

