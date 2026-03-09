@{
    # Enforce all default rules EXCEPT those explicitly excluded below.
    # Run locally: Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    ExcludeRules = @(
        # False positive rate is too high in WinForms — event handler params
        # (e.g. $eventSender) are required by delegate signatures even when unused.
        'PSReviewUnusedParameter'

        # This is a desktop GUI app. Write-Host is intentional for console output.
        'PSAvoidUsingWriteHost'

        # Flags legitimate plurals like Get-DiffLines, Get-Duplicates, Get-StandardCases.
        # These functions correctly return collections.
        'PSUseSingularNouns'

        # Requires SupportsShouldProcess on every Set-/Remove-/Write- function.
        # Overkill for an internal desktop tool with no pipeline usage.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
