function Get-BtnPrevHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['CurrentIndex'] -gt 0) {
            Show-Tumor -Index ($ScriptVars['CurrentIndex'] - 1)
        }
    }
}
