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

function Set-XmlSyntaxHighlighting {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$XmlText
    )

    $colorNaaccrId = [System.Drawing.Color]::Blue
    $colorValue = [System.Drawing.Color]::FromArgb(0, 128, 128)  # Teal

    # Set the text first
    $RichTextBox.Text = $XmlText
    $RichTextBox.SelectAll()
    $RichTextBox.SelectionColor = [System.Drawing.Color]::Black
    $RichTextBox.SelectionFont = $RichTextBox.Font

    # Use the RichTextBox.Text for indexing (it normalizes line endings)
    $rtbText = $RichTextBox.Text

    # Find naaccrId="value" and highlight just the value
    $prefix = 'naaccrId="'
    $prefixLen = $prefix.Length

    $startIndex = 0
    while ($true) {
        $pos = $rtbText.IndexOf($prefix, $startIndex)
        if ($pos -lt 0) { break }

        $valueStart = $pos + $prefixLen
        $valueEnd = $rtbText.IndexOf('"', $valueStart)
        if ($valueEnd -lt 0) { break }

        $valueLen = $valueEnd - $valueStart
        if ($valueLen -gt 0) {
            $RichTextBox.Select($valueStart, $valueLen)
            $RichTextBox.SelectionColor = $colorNaaccrId
        }

        $startIndex = $valueEnd + 1
    }

    # Teal Item values: find </Item> and work backwards to the > that starts the content
    $closingTag = '</Item>'

    $startIndex = 0
    while ($true) {
        $closePos = $rtbText.IndexOf($closingTag, $startIndex)
        if ($closePos -lt 0) { break }

        # Search backwards from </Item> to find the > that ends the opening tag
        $searchStart = [Math]::Max(0, $closePos - 500)  # Don't search too far back
        $segment = $rtbText.Substring($searchStart, $closePos - $searchStart)
        $openPos = $segment.LastIndexOf('">')

        if ($openPos -ge 0) {
            $valueStart = $searchStart + $openPos + 2  # +2 for ">
            $valueLen = $closePos - $valueStart
            if ($valueLen -gt 0) {
                $RichTextBox.Select($valueStart, $valueLen)
                $RichTextBox.SelectionColor = $colorValue
            }
        }

        $startIndex = $closePos + $closingTag.Length
    }

    # Reset selection to beginning
    $RichTextBox.Select(0, 0)
    $RichTextBox.ScrollToCaret()
}

function Set-Hl7SyntaxHighlighting {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$Hl7Text
    )

    # Define colors
    $colorSegment    = [System.Drawing.Color]::Blue
    $colorSeparator  = [System.Drawing.Color]::FromArgb(128, 128, 128)  # Gray
    $colorText       = [System.Drawing.Color]::Black
    $colorMsh        = [System.Drawing.Color]::FromArgb(128, 0, 128)    # Purple for MSH
    $colorPid        = [System.Drawing.Color]::FromArgb(0, 128, 0)      # Green for PID
    $colorObxId      = [System.Drawing.Color]::FromArgb(0, 128, 128)    # Teal for OBX identifier

    # Set the text first
    $RichTextBox.Text = $Hl7Text
    $RichTextBox.SelectAll()
    $RichTextBox.SelectionColor = $colorText
    $RichTextBox.SelectionFont = $RichTextBox.Font

    # Use RichTextBox.Text for indexing (normalizes line endings)
    $Hl7Text = $RichTextBox.Text

    # Known HL7 segment names
    $segmentNames = @(
        'MSH', 'PID', 'PV1', 'PV2', 'ORC', 'OBR', 'OBX', 'NTE', 'NK1',
        'IN1', 'IN2', 'GT1', 'AL1', 'DG1', 'PR1', 'ROL', 'EVN', 'MRG',
        'ZPD', 'ZDS', 'SPM', 'TXA', 'PD1', 'DB1', 'DRG', 'FT1', 'ACC'
    )

    # Highlight segment names at the start of lines
    foreach ($segName in $segmentNames) {
        $pattern = "(?m)^$segName(?=\|)"
        $regexMatches = [regex]::Matches($Hl7Text, $pattern)
        foreach ($match in $regexMatches) {
            $RichTextBox.Select($match.Index, $match.Length)
            # Use different colors for different segment types
            switch ($segName) {
                'MSH' { $RichTextBox.SelectionColor = $colorMsh }
                'PID' { $RichTextBox.SelectionColor = $colorPid }
                default { $RichTextBox.SelectionColor = $colorSegment }
            }
            $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                $RichTextBox.Font.FontFamily,
                $RichTextBox.Font.Size,
                [System.Drawing.FontStyle]::Bold
            )
        }
    }

    # Highlight PID-5 (Patient Name) - bold the entire field including all components
    # PID|1|...|...|...|NAME^COMPONENTS^HERE|...
    # PID-5 is the 5th field after PID (fields are 1-indexed, but PID itself counts)
    $pidPattern = '(?m)^PID\|'
    $pidMatches = [regex]::Matches($Hl7Text, $pidPattern)
    foreach ($pidMatch in $pidMatches) {
        # Find the segment from match start to end of line
        $lineEndIndex = $Hl7Text.IndexOf("`n", $pidMatch.Index)
        if ($lineEndIndex -lt 0) { $lineEndIndex = $Hl7Text.Length }
        $pidLine = $Hl7Text.Substring($pidMatch.Index, $lineEndIndex - $pidMatch.Index)

        # Split by | to find field 5 (0=PID, 1=SetID, 2=PatientID, 3=PatientIDList, 4=AltPatientID, 5=PatientName)
        $fields = $pidLine -split '\|'
        if ($fields.Count -gt 5) {
            # Calculate the position of field 5
            $fieldStart = $pidMatch.Index
            for ($i = 0; $i -lt 5; $i++) {
                $fieldStart += $fields[$i].Length + 1  # +1 for the |
            }
            $field5Length = $fields[5].Length
            if ($field5Length -gt 0) {
                $RichTextBox.Select($fieldStart, $field5Length)
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }
    }

    # Highlight OBX-3.1 (Observation Identifier) and bold OBX-5.1 (Observation Value)
    # OBX|1|TX|CODE^Description|...|VALUE|...
    $obxPattern = '(?m)^OBX\|'
    $obxMatches = [regex]::Matches($Hl7Text, $obxPattern)
    foreach ($obxMatch in $obxMatches) {
        $lineEndIndex = $Hl7Text.IndexOf("`n", $obxMatch.Index)
        if ($lineEndIndex -lt 0) { $lineEndIndex = $Hl7Text.Length }
        $obxLine = $Hl7Text.Substring($obxMatch.Index, $lineEndIndex - $obxMatch.Index)

        # Split by | to find fields
        # 0=OBX, 1=SetID, 2=ValueType, 3=ObservationIdentifier, 4=ObservationSubID, 5=ObservationValue
        $fields = $obxLine -split '\|'

        # Highlight OBX-3.1 (first component of field 3)
        if ($fields.Count -gt 3 -and $fields[3].Length -gt 0) {
            $fieldStart = $obxMatch.Index
            for ($i = 0; $i -lt 3; $i++) {
                $fieldStart += $fields[$i].Length + 1
            }
            # Get just the first component (before ^)
            $components = $fields[3] -split '\^'
            $comp1Length = $components[0].Length
            if ($comp1Length -gt 0) {
                $RichTextBox.Select($fieldStart, $comp1Length)
                $RichTextBox.SelectionColor = $colorObxId
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }

        # Bold OBX-5.1 (first component of field 5 - the observation value)
        if ($fields.Count -gt 5 -and $fields[5].Length -gt 0) {
            $fieldStart = $obxMatch.Index
            for ($i = 0; $i -lt 5; $i++) {
                $fieldStart += $fields[$i].Length + 1
            }
            # Get just the first component (before ^)
            $components = $fields[5] -split '\^'
            $comp1Length = $components[0].Length
            if ($comp1Length -gt 0) {
                $RichTextBox.Select($fieldStart, $comp1Length)
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }
    }

    # Highlight field separators (|)
    $sepPattern = '\|'
    $regexMatches = [regex]::Matches($Hl7Text, $sepPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Highlight component separators (^)
    $compPattern = '\^'
    $regexMatches = [regex]::Matches($Hl7Text, $compPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Highlight subcomponent separators (&)
    $subPattern = '&'
    $regexMatches = [regex]::Matches($Hl7Text, $subPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Highlight repetition separators (~)
    $repPattern = '~'
    $regexMatches = [regex]::Matches($Hl7Text, $repPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Reset selection
    $RichTextBox.Select(0, 0)
    $RichTextBox.ScrollToCaret()
}

function Set-Hl7PanelHighlighting {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [int]$StartOffset = 0
    )

    # Define colors
    $colorSegment    = [System.Drawing.Color]::Blue
    $colorSeparator  = [System.Drawing.Color]::FromArgb(128, 128, 128)  # Gray
    $colorMsh        = [System.Drawing.Color]::FromArgb(128, 0, 128)    # Purple for MSH
    $colorPid        = [System.Drawing.Color]::FromArgb(0, 128, 0)      # Green for PID
    $colorObxId      = [System.Drawing.Color]::FromArgb(0, 128, 128)    # Teal for OBX identifier

    $rtbText = $RichTextBox.Text
    $textToProcess = $rtbText.Substring($StartOffset)

    # Known HL7 segment names
    $segmentNames = @(
        'MSH', 'PID', 'PV1', 'PV2', 'ORC', 'OBR', 'OBX', 'NTE', 'NK1',
        'IN1', 'IN2', 'GT1', 'AL1', 'DG1', 'PR1', 'ROL', 'EVN', 'MRG',
        'ZPD', 'ZDS', 'SPM', 'TXA', 'PD1', 'DB1', 'DRG', 'FT1', 'ACC'
    )

    # Highlight segment names at the start of lines
    foreach ($segName in $segmentNames) {
        $pattern = "(?m)^$segName(?=\|)"
        $regexMatches = [regex]::Matches($textToProcess, $pattern)
        foreach ($match in $regexMatches) {
            $RichTextBox.Select($StartOffset + $match.Index, $match.Length)
            switch ($segName) {
                'MSH' { $RichTextBox.SelectionColor = $colorMsh }
                'PID' { $RichTextBox.SelectionColor = $colorPid }
                default { $RichTextBox.SelectionColor = $colorSegment }
            }
            $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                $RichTextBox.Font.FontFamily,
                $RichTextBox.Font.Size,
                [System.Drawing.FontStyle]::Bold
            )
        }
    }

    # Highlight PID-5 (Patient Name)
    $pidPattern = '(?m)^PID\|'
    $pidMatches = [regex]::Matches($textToProcess, $pidPattern)
    foreach ($pidMatch in $pidMatches) {
        $lineEndIndex = $textToProcess.IndexOf("`n", $pidMatch.Index)
        if ($lineEndIndex -lt 0) { $lineEndIndex = $textToProcess.Length }
        $pidLine = $textToProcess.Substring($pidMatch.Index, $lineEndIndex - $pidMatch.Index)

        $fields = $pidLine -split '\|'
        if ($fields.Count -gt 5) {
            $fieldStart = $pidMatch.Index
            for ($i = 0; $i -lt 5; $i++) {
                $fieldStart += $fields[$i].Length + 1
            }
            $field5Length = $fields[5].Length
            if ($field5Length -gt 0) {
                $RichTextBox.Select($StartOffset + $fieldStart, $field5Length)
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }
    }

    # Highlight OBX-3.1 and OBX-5
    $obxPattern = '(?m)^OBX\|'
    $obxMatches = [regex]::Matches($textToProcess, $obxPattern)
    foreach ($obxMatch in $obxMatches) {
        $lineEndIndex = $textToProcess.IndexOf("`n", $obxMatch.Index)
        if ($lineEndIndex -lt 0) { $lineEndIndex = $textToProcess.Length }
        $obxLine = $textToProcess.Substring($obxMatch.Index, $lineEndIndex - $obxMatch.Index)

        $fields = $obxLine -split '\|'

        # Highlight OBX-3.1
        if ($fields.Count -gt 3 -and $fields[3].Length -gt 0) {
            $fieldStart = $obxMatch.Index
            for ($i = 0; $i -lt 3; $i++) {
                $fieldStart += $fields[$i].Length + 1
            }
            $components = $fields[3] -split '\^'
            $comp1Length = $components[0].Length
            if ($comp1Length -gt 0) {
                $RichTextBox.Select($StartOffset + $fieldStart, $comp1Length)
                $RichTextBox.SelectionColor = $colorObxId
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }

        # Bold OBX-5
        if ($fields.Count -gt 5 -and $fields[5].Length -gt 0) {
            $fieldStart = $obxMatch.Index
            for ($i = 0; $i -lt 5; $i++) {
                $fieldStart += $fields[$i].Length + 1
            }
            $comp1Length = $fields[5].Length
            if ($comp1Length -gt 0) {
                $RichTextBox.Select($StartOffset + $fieldStart, $comp1Length)
                $RichTextBox.SelectionFont = New-Object System.Drawing.Font(
                    $RichTextBox.Font.FontFamily,
                    $RichTextBox.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                )
            }
        }
    }

    # Highlight separators (|)
    $sepPattern = '\|'
    $regexMatches = [regex]::Matches($textToProcess, $sepPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($StartOffset + $match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Highlight component separators (^)
    $compPattern = '\^'
    $regexMatches = [regex]::Matches($textToProcess, $compPattern)
    foreach ($match in $regexMatches) {
        $RichTextBox.Select($StartOffset + $match.Index, $match.Length)
        $RichTextBox.SelectionColor = $colorSeparator
    }

    # Reset selection
    $RichTextBox.Select(0, 0)
}
