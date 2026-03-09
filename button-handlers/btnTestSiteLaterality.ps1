# btnTestSiteLaterality.ps1
# Handlers for Test Site/Laterality Heuristics menu items

function Get-BtnTestSiteLatCurrentHandler {
    <#
    .SYNOPSIS
    Returns script block for "Test current record (Site/Lat)" menu click

    .PARAMETER Controls
    Hashtable of UI controls
    #>
    param(
        [hashtable]$Controls
    )

    return {
        Invoke-TestSiteLatCurrent -Controls $Controls
    }
}

function Get-BtnTestSiteLatCustomHandler {
    <#
    .SYNOPSIS
    Returns script block for "Test custom text (Site/Lat)" menu click

    .PARAMETER Controls
    Hashtable of UI controls
    #>
    param(
        [hashtable]$Controls
    )

    return {
        Invoke-TestSiteLatCustom -Controls $Controls
    }
}

function Invoke-TestSiteLatCurrent {
    <#
    .SYNOPSIS
    Test site/laterality heuristics on the currently selected record (XML or HL7)

    .PARAMETER Controls
    Hashtable of UI controls
    #>
    param(
        [hashtable]$Controls
    )

    $fileType = $script:FileType

    if ($fileType -ne 'xml' -and $fileType -ne 'hl7') {
        [System.Windows.Forms.MessageBox]::Show(
            "No file loaded. This feature works with NAACCR XML or HL7 files.",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    # Get current index
    $idx = [int]$script:CurrentIndex

    if ($fileType -eq 'hl7') {
        Invoke-TestSiteLatCurrentHl7 -Controls $Controls -Index $idx
    }
    else {
        Invoke-TestSiteLatCurrentXml -Controls $Controls -Index $idx
    }
}

function Invoke-TestSiteLatCurrentXml {
    <#
    .SYNOPSIS
    Test site/laterality heuristics on the currently selected XML record
    #>
    param(
        [hashtable]$Controls,
        [int]$Index
    )

    if ($script:Tumors.Count -eq 0 -or -not $script:XmlDoc -or -not $script:NsMgr) {
        [System.Windows.Forms.MessageBox]::Show(
            "No XML document loaded.",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
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

        $tumor = $script:Tumors[$Index]
        $nsMgr = $script:NsMgr

        # Extract text from the tumor's text fields (same fields used in assign-site-laterality.ps1)
        # May need to re-evaluate this at some point--NOAH puts some path info in Lab Tests for instance
        $textPath = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcPath"
        $textPe = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcPe"
        $textLab = Get-TumorItemValue -Tumor $tumor -NsMgr $nsMgr -ItemId "textDxProcLabTests"

        # Combine text (same logic as assign-site-laterality.ps1)
        # May also need to re-evaluate this. May need to just include textDxProcLabTests by default
        $textCombined = (("textDxProcPath: " + $textPath + "`n`ntextDxProcPe: " + $textPe)).Trim()
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

        $result = Test-SiteLateralityHeuristics -Text $textCombined

        $result.SourceInfo = "Tumor $($Index + 1) of $($script:Tumors.Count)"
        $result.TextLength = $textCombined.Length

        Show-TestSiteLateralityResults -Result $result -SourceText $textCombined

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

function Invoke-TestSiteLatCurrentHl7 {
    <#
    .SYNOPSIS
    Test site/laterality heuristics on the currently selected HL7 message
    #>
    param(
        [hashtable]$Controls,
        [int]$Index
    )

    $messages = $script:Hl7Messages

    if (-not $messages -or $messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No HL7 messages loaded.",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if ($Index -lt 0 -or $Index -ge $messages.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a message first (click a row in the left grid).",
            "Test Site/Laterality",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    try {
        $Controls['lblStatus'].Text = "Testing site/laterality on current HL7 message..."
        $Controls['form'].Refresh()

        $message = $messages[$Index]

        $obxSegments = @()
        if ($message.Segments -and $message.Segments.ContainsKey("OBX")) {
            $obxSegments = @($message.Segments["OBX"])
        }

        if ($obxSegments.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No OBX segments found in the current HL7 message.",
                "Test Site/Laterality",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $Controls['lblStatus'].Text = "Site/Lat test: no OBX segments"
            return
        }

        $config = Get-ObxSkipConfig
        $skipCodes = @($config.skipCodes)

        $textCombined = Get-FilteredObxTextContent -ObxSegments $obxSegments -SkipCodes $skipCodes

        if ([string]::IsNullOrWhiteSpace($textCombined)) {
            $skippedInfo = if ($skipCodes.Count -gt 0) { " (skipped codes: $($skipCodes -join ', '))" } else { "" }
            [System.Windows.Forms.MessageBox]::Show(
                "No text found in OBX-5 values after filtering.$skippedInfo",
                "Test Site/Laterality",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $Controls['lblStatus'].Text = "Site/Lat test: no text after filtering"
            return
        }

        $result = Test-SiteLateralityHeuristics -Text $textCombined

        $patientInfo = if ($message.PatientName) { " ($($message.PatientName))" } else { "" }
        $result.SourceInfo = "HL7 Message $($Index + 1) of $($messages.Count)$patientInfo"
        $result.TextLength = $textCombined.Length

        Show-TestSiteLateralityResults -Result $result -ObxSegments $obxSegments -SkipCodes $skipCodes

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
    #>
    param(
        [hashtable]$Controls
    )

    # Show input dialog
    $text = Show-TestSiteLateralityDialog

    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    try {
        $Controls['lblStatus'].Text = "Testing site/laterality heuristics..."
        $Controls['form'].Refresh()

        $result = Test-SiteLateralityHeuristics -Text $text

        $result.SourceInfo = "Custom text input"
        $result.TextLength = $text.Length

        Show-TestSiteLateralityResults -Result $result -SourceText $text

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
