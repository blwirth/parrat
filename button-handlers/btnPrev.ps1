function Get-BtnPrevHandler {
    return {
        try {
            $currentIdx = $script:CurrentIndex

            if ($currentIdx -gt 0) {
                $newIndex = $currentIdx - 1

                $fileType = $script:FileType

                if ($fileType -eq 'hl7') {
                    Show-Hl7Message -Index $newIndex -Messages $script:Hl7Messages -Controls $script:Controls
                }
                else {
                    Show-Tumor -Index $newIndex
                }
            }
        }
        catch {
            Write-ParatError -Message "Previous record failed" -Action "PREV" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error navigating to previous record: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}


