function Get-BtnPrevHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        if ($script:CurrentIndex -gt 0) {
            $newIndex = $script:CurrentIndex - 1
            
            # Dispatch to appropriate viewer based on file type
            if ($script:FileType -eq 'hl7') {
                Show-Hl7Message -Index $newIndex
            }
            else {
                Show-Tumor -Index $newIndex
            }
        }
    }
}
