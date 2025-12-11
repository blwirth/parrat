function Get-BtnNextHandler {
    param(
        [hashtable]$ScriptVars
    )
    
    return {
        if ($ScriptVars['CurrentIndex'] -ge 0 -and $ScriptVars['CurrentIndex'] -lt ($ScriptVars['Tumors'].Count - 1)) {
            Show-Tumor -Index ($ScriptVars['CurrentIndex'] + 1)
        }
    }
}
