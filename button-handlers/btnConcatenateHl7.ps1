function Get-BtnConcatenateHl7Handler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        Start-ConcatenateHl7 -Controls $Controls -ScriptVars $ScriptVars
    }.GetNewClosure()
}

