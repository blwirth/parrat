function Get-BtnNextHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        # Determine record count based on file type
        $recordCount = 0
        if ($script:FileType -eq 'hl7') {
            $recordCount = $script:Hl7Messages.Count
        }
        else {
            $recordCount = $script:Tumors.Count
        }
        
        if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt ($recordCount - 1)) {
            $newIndex = $script:CurrentIndex + 1
            
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
