function Get-BtnDiffFilesHandler {
    <#
    .SYNOPSIS
    Returns a scriptblock handler for the Diff Files button.
    
    .DESCRIPTION
    Opens a file picker to select two NAACCR XML files and displays a side-by-side diff.
    #>
    
    return {
        Show-FileDiff
    }
}
