# xml-helpers.ps1
# Shared utilities for NAACCR XML processing

# NAACCR IDs to bold in the right column
$script:BoldIds = @(
    "nameFirst",
    "nameLast",
    "nameMiddle",
    "dateOfBirth",
    "dateOfDiagnosis",
    "primarySite",
    "laterality"
)

# NAACCR IDs that are pathology text fields (middle column)
$script:TextFieldIds = @(
    "textDxProcLabTests",
    "textDxProcPath",
    "textDxProcPe",
    "textHistologyTitle"
)

function Add-LineToRichTextBox {
    param(
        [System.Windows.Forms.RichTextBox]$Box,
        [string]$Text,
        [bool]$Bold = $false
    )

    $Box.SelectionStart  = $Box.TextLength
    $Box.SelectionLength = 0

    if ($Bold) {
        $Box.SelectionFont = New-Object System.Drawing.Font(
            $Box.Font.FontFamily,
            $Box.Font.Size,
            [System.Drawing.FontStyle]::Bold
        )
    }
    else {
        $Box.SelectionFont = $Box.Font
    }

    $Box.AppendText($Text + "`r`n")
}

function Get-TumorLabel {
    param(
        [int]$Index,
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $tumor   = $Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

    $nameLast  = ""
    $nameFirst = ""
    $dxDate    = ""

    if ($patient -ne $null) {
        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
        if ($nlNode) { $nameLast  = $nlNode.InnerText }
        if ($nfNode) { $nameFirst = $nfNode.InnerText }
    }

    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $NsMgr)
    if ($dxNode) { $dxDate = $dxNode.InnerText }

    return "Idx {0} - {1}, {2} - Dx {3}" -f ($Index + 1), $nameLast, $nameFirst, $dxDate
}

function Get-NaaccrItemMap {
    param(
        [int]$Index,
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $tumor   = $Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

    $map = @{}

    # Patient items
    if ($patient -ne $null) {
        $pItems = $patient.SelectNodes("./n:Item", $NsMgr)
        foreach ($item in $pItems) {
            $id  = $item.GetAttribute("naaccrId")
            $val = $item.InnerText
            # Key format: "P|naaccrId"
            $map["P|$id"] = $val
        }
    }

    # Tumor items
    $tItems = $tumor.SelectNodes("./n:Item", $NsMgr)
    foreach ($item in $tItems) {
        $id  = $item.GetAttribute("naaccrId")
        $val = $item.InnerText
        # Key format: "T|naaccrId"
        $map["T|$id"] = $val
    }

    return $map
}

function Format-Xml {
    param(
        [string]$Xml
    )

    if ([string]::IsNullOrWhiteSpace($Xml)) {
        return $Xml
    }

    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    $doc.LoadXml($Xml)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $doc.Save($xw)
    $xw.Flush()
    $sw.ToString()
}