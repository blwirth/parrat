function Get-DiffLines {
    param(
        [string[]]$LinesA,
        [string[]]$LinesB
    )

    if ($null -eq $LinesA) { $LinesA = @() }
    if ($null -eq $LinesB) { $LinesB = @() }

    [int]$lenA = @($LinesA).Count
    [int]$lenB = @($LinesB).Count

    # LCS dynamic programming matrix
    $lcs = New-Object 'int[,]' ($lenA + 1), ($lenB + 1)

    for ([int]$i = 1; $i -le $lenA; $i++) {
        for ([int]$j = 1; $j -le $lenB; $j++) {
            [int]$iMinus1 = $i - 1
            [int]$jMinus1 = $j - 1

            if ($LinesA[$iMinus1] -eq $LinesB[$jMinus1]) {
                $lcs[$i, $j] = $lcs[$iMinus1, $jMinus1] + 1
            }
            else {
                $val1 = $lcs[$iMinus1, $j]
                $val2 = $lcs[$i, $jMinus1]
                $lcs[$i, $j] = [Math]::Max($val1, $val2)
            }
        }
    }

    $diffLines = New-Object System.Collections.ArrayList
    [int]$i = $lenA
    [int]$j = $lenB

    while ($i -gt 0 -or $j -gt 0) {
        [int]$iMinus1 = $i - 1
        [int]$jMinus1 = $j - 1

        if ($i -gt 0 -and $j -gt 0 -and $LinesA[$iMinus1] -eq $LinesB[$jMinus1]) {
            [void]$diffLines.Insert(0, @{
                LineNumA = $i
                LineNumB = $j
                Status = 'Unchanged'
                ContentA = $LinesA[$iMinus1]
                ContentB = $LinesB[$jMinus1]
            })
            $i--
            $j--
        }
        elseif ($j -gt 0 -and ($i -eq 0 -or $lcs[$i, $jMinus1] -ge $lcs[$iMinus1, $j])) {
            [void]$diffLines.Insert(0, @{
                LineNumA = $null
                LineNumB = $j
                Status = 'Added'
                ContentA = ''
                ContentB = $LinesB[$jMinus1]
            })
            $j--
        }
        elseif ($i -gt 0) {
            [void]$diffLines.Insert(0, @{
                LineNumA = $i
                LineNumB = $null
                Status = 'Deleted'
                ContentA = $LinesA[$iMinus1]
                ContentB = ''
            })
            $i--
        }
    }

    return $diffLines
}

function Get-TumorLabel {
    param(
        [int]$Index
    )

    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        throw "Get-TumorLabel: script:Tumors is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
        throw "Get-TumorLabel: Index $Index is out of range (0..$($script:Tumors.Count - 1))."
    }

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $nameLast          = ""
    $nameFirst         = ""
    $dxDate            = ""
    $pathReportNumber1 = ""

    if ($patient -ne $null) {
        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']",  $script:NsMgr)
        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $script:NsMgr)
        if ($nlNode) { $nameLast  = $nlNode.InnerText }
        if ($nfNode) { $nameFirst = $nfNode.InnerText }
    }

    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $script:NsMgr)
    if ($dxNode) { $dxDate = $dxNode.InnerText }

    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $script:NsMgr)
    if ($dxNode) { $pathReportNumber1 = $dxNode.InnerText }

    return "Idx {0} - {1}, {2} - Dx {3} - Path Number {4}" -f ($Index + 1), $nameLast, $nameFirst, $dxDate, $pathReportNumber1
}

function Get-FormattedTumorXml {
    param(
        [int]$Index
    )

    $tumor = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`n"
    $settings.OmitXmlDeclaration = $true

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $patient.WriteTo($xw)
    $xw.Flush()
    $xw.Close()

    $formatted = $sw.ToString()
    $sw.Close()

    $lines = @($formatted -split "`n" | ForEach-Object { $_.TrimEnd("`r", " ") })
    return $lines
}

function Show-NaaccrTumorDiff {
    param(
        [int]$IndexA,
        [int]$IndexB
    )

    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Diff")
        return
    }

    if ($IndexA -lt 0 -or $IndexA -ge $script:Tumors.Count -or
        $IndexB -lt 0 -or $IndexB -ge $script:Tumors.Count) {
        [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
        return
    }

    $labelA = Get-TumorLabel -Index $IndexA
    $labelB = Get-TumorLabel -Index $IndexB

    $linesA = Get-FormattedTumorXml -Index $IndexA
    $linesB = Get-FormattedTumorXml -Index $IndexB
    $diffLines = Get-DiffLines -LinesA $linesA -LinesB $linesB

    $addedCount = ($diffLines | Where-Object { $_.Status -eq 'Added' }).Count
    $deletedCount = ($diffLines | Where-Object { $_.Status -eq 'Deleted' }).Count
    $unchangedCount = ($diffLines | Where-Object { $_.Status -eq 'Unchanged' }).Count

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "Diff: Record A vs Record B"
    $diffForm.Width = 1400
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 50)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $summaryText = "A: $labelA`nB: $labelB`n"
    $summaryText += "Changes: +$addedCount added, -$deletedCount removed, $unchangedCount unchanged"
    $lblSummary.Text = $summaryText

    $rtbDiff = New-Object System.Windows.Forms.RichTextBox
    $rtbDiff.Location = New-Object System.Drawing.Point(10, 65)
    $rtbDiff.Size = New-Object System.Drawing.Size(1360, 750)
    $rtbDiff.Anchor = 'Top,Left,Right,Bottom'
    $rtbDiff.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbDiff.ReadOnly = $true
    $rtbDiff.WordWrap = $false
    $rtbDiff.ScrollBars = 'Both'

    $lineNumA = 0
    $lineNumB = 0

    foreach ($line in $diffLines) {
        $prefix = ""
        $color = [System.Drawing.Color]::Black
        $bgColor = [System.Drawing.Color]::White
        $lineNumText = ""

        switch ($line.Status) {
            'Unchanged' {
                $lineNumA++
                $lineNumB++
                $prefix = "  "
                $color = [System.Drawing.Color]::Black
                $bgColor = [System.Drawing.Color]::White
                $lineNumText = "{0,4} {1,4}  " -f $lineNumA, $lineNumB
            }
            'Added' {
                $lineNumB++
                $prefix = "+ "
                $color = [System.Drawing.Color]::DarkGreen
                $bgColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
                $lineNumText = "     {0,4}  " -f $lineNumB
            }
            'Deleted' {
                $lineNumA++
                $prefix = "- "
                $color = [System.Drawing.Color]::DarkRed
                $bgColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
                $lineNumText = "{0,4}      " -f $lineNumA
            }
        }

        $content = if ($line.Status -eq 'Added') { $line.ContentB } else { $line.ContentA }
        $text = "$lineNumText$prefix$content`n"

        $rtbDiff.SelectionStart = $rtbDiff.TextLength
        $rtbDiff.SelectionLength = 0
        $rtbDiff.SelectionColor = $color
        $rtbDiff.SelectionBackColor = $bgColor
        $rtbDiff.AppendText($text)
    }

    $rtbDiff.SelectionStart = 0
    $rtbDiff.ScrollToCaret()

    $lblLegend = New-Object System.Windows.Forms.Label
    $lblLegend.Location = New-Object System.Drawing.Point(10, 825)
    $lblLegend.Size = New-Object System.Drawing.Size(700, 20)
    $lblLegend.Text = "Legend:  + Added (in B only)  |  - Removed (in A only)  |  (no prefix) Unchanged  |  Line numbers: A  B"
    $lblLegend.ForeColor = [System.Drawing.Color]::Gray
    $lblLegend.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1280, 825)
    $btnClose.Size = New-Object System.Drawing.Size(90, 28)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ $diffForm.Close() })

    $diffForm.Controls.AddRange(@($lblSummary, $rtbDiff, $lblLegend, $btnClose))
    [void]$diffForm.ShowDialog()
}

function Get-Hl7MessageLabel {
    param(
        [int]$Index
    )

    if (-not $script:Hl7Messages -or $script:Hl7Messages.Count -eq 0) {
        throw "Get-Hl7MessageLabel: script:Hl7Messages is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Hl7Messages.Count) {
        throw "Get-Hl7MessageLabel: Index $Index is out of range (0..$($script:Hl7Messages.Count - 1))."
    }

    $message = $script:Hl7Messages[$Index]

    $patientName = $message.PatientName
    $messageType = $message.MessageType
    $patientId   = $message.PatientId

    return "Idx {0} - {1} ({2}) - ID: {3}" -f ($Index + 1), $patientName, $messageType, $patientId
}

function Get-Hl7MessageLines {
    param(
        [int]$Index
    )

    $message = $script:Hl7Messages[$Index]
    $lines = New-Object System.Collections.ArrayList

    # Standard HL7 segment order
    $segmentOrder = @('MSH', 'PID', 'PV1', 'ORC', 'OBR', 'OBX', 'NTE', 'ZPD')

    foreach ($segType in $segmentOrder) {
        if ($message.Segments.ContainsKey($segType)) {
            foreach ($segment in $message.Segments[$segType]) {
                [void]$lines.Add($segment)
            }
        }
    }

    # Add any remaining segment types not in the standard order
    foreach ($segType in $message.Segments.Keys) {
        if ($segType -notin $segmentOrder) {
            foreach ($segment in $message.Segments[$segType]) {
                [void]$lines.Add($segment)
            }
        }
    }

    return @($lines)
}

function Show-Hl7MessageDiff {
    param(
        [int]$IndexA,
        [int]$IndexB
    )

    if (-not $script:Hl7Messages -or $script:Hl7Messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No HL7 messages loaded.", "Diff")
        return
    }

    if ($IndexA -lt 0 -or $IndexA -ge $script:Hl7Messages.Count -or
        $IndexB -lt 0 -or $IndexB -ge $script:Hl7Messages.Count) {
        [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
        return
    }

    $labelA = Get-Hl7MessageLabel -Index $IndexA
    $labelB = Get-Hl7MessageLabel -Index $IndexB

    $linesA = Get-Hl7MessageLines -Index $IndexA
    $linesB = Get-Hl7MessageLines -Index $IndexB
    $diffLines = Get-DiffLines -LinesA $linesA -LinesB $linesB

    $addedCount = ($diffLines | Where-Object { $_.Status -eq 'Added' }).Count
    $deletedCount = ($diffLines | Where-Object { $_.Status -eq 'Deleted' }).Count
    $unchangedCount = ($diffLines | Where-Object { $_.Status -eq 'Unchanged' }).Count

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "HL7 Diff: Record A vs Record B"
    $diffForm.Width = 1400
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 50)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $summaryText = "A: $labelA`nB: $labelB`n"
    $summaryText += "Changes: +$addedCount added, -$deletedCount removed, $unchangedCount unchanged"
    $lblSummary.Text = $summaryText

    $rtbDiff = New-Object System.Windows.Forms.RichTextBox
    $rtbDiff.Location = New-Object System.Drawing.Point(10, 65)
    $rtbDiff.Size = New-Object System.Drawing.Size(1360, 750)
    $rtbDiff.Anchor = 'Top,Left,Right,Bottom'
    $rtbDiff.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbDiff.ReadOnly = $true
    $rtbDiff.WordWrap = $false
    $rtbDiff.ScrollBars = 'Both'

    $lineNumA = 0
    $lineNumB = 0

    foreach ($line in $diffLines) {
        $prefix = ""
        $color = [System.Drawing.Color]::Black
        $bgColor = [System.Drawing.Color]::White
        $lineNumText = ""

        switch ($line.Status) {
            'Unchanged' {
                $lineNumA++
                $lineNumB++
                $prefix = "  "
                $color = [System.Drawing.Color]::Black
                $bgColor = [System.Drawing.Color]::White
                $lineNumText = "{0,4} {1,4}  " -f $lineNumA, $lineNumB
            }
            'Added' {
                $lineNumB++
                $prefix = "+ "
                $color = [System.Drawing.Color]::DarkGreen
                $bgColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
                $lineNumText = "     {0,4}  " -f $lineNumB
            }
            'Deleted' {
                $lineNumA++
                $prefix = "- "
                $color = [System.Drawing.Color]::DarkRed
                $bgColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
                $lineNumText = "{0,4}      " -f $lineNumA
            }
        }

        $content = if ($line.Status -eq 'Added') { $line.ContentB } else { $line.ContentA }
        $text = "$lineNumText$prefix$content`n"

        $rtbDiff.SelectionStart = $rtbDiff.TextLength
        $rtbDiff.SelectionLength = 0
        $rtbDiff.SelectionColor = $color
        $rtbDiff.SelectionBackColor = $bgColor
        $rtbDiff.AppendText($text)
    }

    $rtbDiff.SelectionStart = 0
    $rtbDiff.ScrollToCaret()

    $lblLegend = New-Object System.Windows.Forms.Label
    $lblLegend.Location = New-Object System.Drawing.Point(10, 825)
    $lblLegend.Size = New-Object System.Drawing.Size(700, 20)
    $lblLegend.Text = "Legend:  + Added (in B only)  |  - Removed (in A only)  |  (no prefix) Unchanged  |  Line numbers: A  B"
    $lblLegend.ForeColor = [System.Drawing.Color]::Gray
    $lblLegend.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1280, 825)
    $btnClose.Size = New-Object System.Drawing.Size(90, 28)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ $diffForm.Close() })

    $diffForm.Controls.AddRange(@($lblSummary, $rtbDiff, $lblLegend, $btnClose))
    [void]$diffForm.ShowDialog()
}