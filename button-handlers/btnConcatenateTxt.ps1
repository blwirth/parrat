function Get-BtnConcatenateTxtHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        Start-ConcatenateTxt -Controls $Controls -ScriptVars $ScriptVars
    }.GetNewClosure()
}


