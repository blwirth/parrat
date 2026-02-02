function Get-BtnPrevHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        try {
            $currentIdx = $global:CurrentIndex
            if ($null -eq $currentIdx -or $currentIdx -lt 0) { $currentIdx = $script:CurrentIndex }

            if ($currentIdx -gt 0) {
                $newIndex = $currentIdx - 1

                $fileType = $global:FileType
                if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }

                if ($fileType -eq 'hl7') {
                    Show-Hl7Message -Index $newIndex -Messages $global:Hl7Messages -Controls $global:AppControls
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


