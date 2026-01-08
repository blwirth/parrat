function Get-BtnNextHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        # Determine record count based on file type
        $fileType = $global:FileType
        if ([string]::IsNullOrEmpty($fileType)) { $fileType = $script:FileType }
        
        $recordCount = 0
        if ($fileType -eq 'hl7') {
            $messages = $global:Hl7Messages
            if ($null -eq $messages) { $messages = $script:Hl7Messages }
            $recordCount = if ($null -ne $messages) { $messages.Count } else { 0 }
        }
        else {
            $recordCount = $script:Tumors.Count
        }
        
        $currentIdx = $global:CurrentIndex
        if ($null -eq $currentIdx -or $currentIdx -lt 0) { $currentIdx = $script:CurrentIndex }
        
        if ($currentIdx -ge 0 -and $currentIdx -lt ($recordCount - 1)) {
            $newIndex = $currentIdx + 1
            
            # Dispatch to appropriate viewer based on file type
            if ($fileType -eq 'hl7') {
                Show-Hl7Message -Index $newIndex -Messages $global:Hl7Messages -Controls $global:AppControls
            }
            else {
                Show-Tumor -Index $newIndex
            }
        }
    }
}
