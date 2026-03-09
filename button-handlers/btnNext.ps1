function Get-BtnNextHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        try {
            $fileType = $script:FileType

            $recordCount = 0
            if ($fileType -eq 'hl7') {
                $recordCount = if ($null -ne $script:Hl7Messages) { $script:Hl7Messages.Count } else { 0 }
            }
            else {
                $recordCount = $script:Tumors.Count
            }

            $currentIdx = $script:CurrentIndex

            if ($currentIdx -ge 0 -and $currentIdx -lt ($recordCount - 1)) {
                $newIndex = $currentIdx + 1

                if ($fileType -eq 'hl7') {
                    Show-Hl7Message -Index $newIndex -Messages $script:Hl7Messages -Controls $script:Controls
                }
                else {
                    Show-Tumor -Index $newIndex
                }
            }
        }
        catch {
            Write-ParatError -Message "Next record failed" -Action "NEXT" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error navigating to next record: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}
