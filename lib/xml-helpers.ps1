# xml-helpers.ps1
# Shared utilities for NAACCR XML processing

$script:BoldIds = @(
    "nameFirst",
    "nameLast",
    "nameMiddle",
    "dateOfBirth",
    "dateOfDiagnosis",
    "primarySite",
    "laterality"
)

$script:TextFieldIds = @(
    "textDxProcLabTests",
    "textDxProcPath",
    "textDxProcPe",
    "textHistologyTitle",
	"textPrimarySiteTitle"
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
    $settings.Indent           = $true
    $settings.NewLineChars     = "`r`n"
    $settings.NewLineHandling  = "Replace"

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $doc.Save($xw)
    $xw.Flush()
    $sw.ToString()
}
