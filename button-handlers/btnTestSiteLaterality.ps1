# btnTestSiteLaterality.ps1
# Handlers for Test Site/Laterality Heuristics menu items

function Get-BtnTestSiteLatCurrentHandler {
    <#
    .SYNOPSIS
    Returns script block for "Test current record (Site/Lat)" menu click

    .PARAMETER Controls
    Hashtable of UI controls

    .PARAMETER ScriptVars
    Hashtable of script variables
    #>
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        Invoke-TestSiteLatCurrent -Controls $Controls -ScriptVars $ScriptVars
    }
}

function Get-BtnTestSiteLatCustomHandler {
    <#
    .SYNOPSIS
    Returns script block for "Test custom text (Site/Lat)" menu click

    .PARAMETER Controls
    Hashtable of UI controls

    .PARAMETER ScriptVars
    Hashtable of script variables
    #>
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        Invoke-TestSiteLatCustom -Controls $Controls -ScriptVars $ScriptVars
    }
}

function Invoke-TestSiteLatCurrent {
    <#
    .SYNOPSIS
    Test site/laterality heuristics on the currently selected XML record

    .PARAMETER Controls
    Hashtable of UI controls

    .PARAMETER ScriptVars
    Hashtable of script variables
    #>
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    # Check for XML file
    $fileType = $script:FileType
    if ($fileType -ne 'xml') {
        [System.Windows.Forms.MessageBox]::Show(
            "No XML file loaded. This feature works with NAACCR XML files.",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    # Get current index
    $idx = $ScriptVars['CurrentIndex']
    if ($null -eq $idx -or $idx -lt 0) {
        $idx = $global:CurrentIndex
    }
    $idx = [int]$idx

    if ($ScriptVars['Tumors'].Count -eq 0 -or -not $ScriptVars['XmlDoc'] -or -not $ScriptVars['NsMgr']) {
        [System.Windows.Forms.MessageBox]::Show(
            "No XML document loaded.",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($idx -lt 0 -or $idx -ge $ScriptVars['Tumors'].Count) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a tumor first (click a row in the left grid).",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    try {
        $Controls['lblStatus'].Text = "Testing site/laterality on current record..."
        $Controls['form'].Refresh()

        # Get the tumor and extract text fields
        $tumor = $ScriptVars['Tumors'][$idx]
        $nsMgr = $ScriptVars['NsMgr']

        # Extract text from the tumor's text fields (same fields used in assign-site-laterality.ps1)
        $textPath = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcPath"
        $textPe = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcPe"
        $textLab = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcLabTests"

        # Combine text (same logic as assign-site-laterality.ps1)
        $textCombined = (($textPath + " " + $textPe)).Trim()
        if (-not $textCombined) {
            $textCombined = $textLab.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($textCombined)) {
            [System.Windows.Forms.MessageBox]::Show(
                "No text found in tumor's pathology text fields (textDxProcPath, textDxProcPe, textDxProcLabTests).",
                "Test Site/Laterality",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $Controls['lblStatus'].Text = "Site/Lat test: no text in record"
            return
        }

        # Run heuristics
        $result = Test-SiteLateralityHeuristics -Text $textCombined

        # Add source info to result for display
        $result.SourceInfo = "Tumor $($idx + 1) of $($ScriptVars['Tumors'].Count)"
        $result.TextLength = $textCombined.Length

        # Show results
        Show-TestSiteLateralityResults -Result $result

        # Update status
        if ($result.SiteCode) {
            $Controls['lblStatus'].Text = "Site/Lat test: $($result.SiteCode) / $($result.LateralityDescription)"
        }
        else {
            $Controls['lblStatus'].Text = "Site/Lat test: No match"
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error testing heuristics: $($_.Exception.Message)",
            "Test Site/Laterality - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "Site/Lat test: error"
    }
}

function Invoke-TestSiteLatCustom {
    <#
    .SYNOPSIS
    Test site/laterality heuristics on custom text entered by user

    .PARAMETER Controls
    Hashtable of UI controls

    .PARAMETER ScriptVars
    Hashtable of script variables
    #>
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    # Show input dialog
    $text = Show-TestSiteLateralityDialog

    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "Testing site/laterality heuristics..."
        $Controls['form'].Refresh()

        # Run heuristics
        $result = Test-SiteLateralityHeuristics -Text $text

        # Show results
        Show-TestSiteLateralityResults -Result $result

        # Update status
        if ($result.SiteCode) {
            $Controls['lblStatus'].Text = "Site/Lat test: $($result.SiteCode) / $($result.LateralityDescription)"
        }
        else {
            $Controls['lblStatus'].Text = "Site/Lat test: No match"
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error testing heuristics: $($_.Exception.Message)",
            "Test Site/Laterality - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        $Controls['lblStatus'].Text = "Site/Lat test: error"
    }
}

function Get-TumorItemValue {
    <#
    .SYNOPSIS
    Get the value of a NAACCR item from a tumor node

    .PARAMETER Tumor
    The tumor XML node

    .PARAMETER NsMgr
    XML namespace manager

    .PARAMETER ItemId
    The naaccrId of the item to retrieve
    #>
    param(
        [System.Xml.XmlNode]$Tumor,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$ItemId
    )

    $node = $Tumor.SelectSingleNode("./n:Item[@naaccrId='$ItemId']", $NsMgr)
    if ($node) {
        return $node.InnerText
    }
    return ""
}
