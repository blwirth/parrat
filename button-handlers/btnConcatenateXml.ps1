function Get-BtnConcatenateXmlHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        Start-ConcatenateXml -Controls $Controls -ScriptVars $ScriptVars
    }.GetNewClosure()
}

