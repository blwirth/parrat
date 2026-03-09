function Get-BtnDiffFilesHandler {
    <#
    .SYNOPSIS
    Returns a scriptblock handler for the Diff Files button.

    .DESCRIPTION
    Opens a file picker to select two NAACCR XML files and displays a side-by-side diff.
    #>

    return {
        try {
            Show-FileDiff
        }
        catch {
            Write-ParatError -Message "File diff failed" -Action "DIFF_FILES" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error during file diff: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}
