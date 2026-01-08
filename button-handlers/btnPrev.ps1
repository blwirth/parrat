function Get-BtnPrevHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        $currentIdx = $global:CurrentIndex
        if ($null -eq $currentIdx -or $currentIdx -lt 0) { $currentIdx = $script:CurrentIndex }
        
        if ($currentIdx -gt 0) {
            $newIndex = $currentIdx - 1
            
            # Dispatch to appropriate viewer based on file type
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
}


