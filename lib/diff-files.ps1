# diff-files.ps1
# File-level diff for NAACCR XML and HL7 files

function Show-FileDiff {
    <#
    .SYNOPSIS
    Opens a dialog to select two NAACCR files (XML or HL7) and displays a side-by-side diff.
    #>

    $dialogResult = Show-FileDiffSetupDialog
    if ($null -eq $dialogResult) {
        return
    }

    $filePathA = $dialogResult.FilePathA
    $filePathB = $dialogResult.FilePathB
    $fileType = $dialogResult.FileType
    $comparisonMode = $dialogResult.ComparisonMode

    $sizeA = (Get-Item $filePathA).Length
    $sizeB = (Get-Item $filePathB).Length
    $maxSize = 10MB

    if ($sizeA -gt $maxSize -or $sizeB -gt $maxSize) {
        $sizeMB_A = [math]::Round($sizeA / 1MB, 2)
        $sizeMB_B = [math]::Round($sizeB / 1MB, 2)
        $result = [System.Windows.Forms.MessageBox]::Show(
            "One or both files are large (File A: ${sizeMB_A}MB, File B: ${sizeMB_B}MB).`n`nThis may take some time to process. Continue?",
            "Large File Warning",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    if ($fileType -eq "hl7") {
        $validationA = Test-Hl7File -FilePath $filePathA
        if (-not $validationA.IsValid) {
            [System.Windows.Forms.MessageBox]::Show(
                "First file is not a valid HL7 file:`n`n$($validationA.Error)",
                "Invalid File",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        $validationB = Test-Hl7File -FilePath $filePathB
        if (-not $validationB.IsValid) {
            [System.Windows.Forms.MessageBox]::Show(
                "Second file is not a valid HL7 file:`n`n$($validationB.Error)",
                "Invalid File",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        try {
            $diffResult = Compare-Hl7Files -FilePathA $filePathA -FilePathB $filePathB -Mode $comparisonMode
            Show-Hl7FileDiffPreview -DiffResult $diffResult -FilePathA $filePathA -FilePathB $filePathB
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error comparing files:`n`n$($_.Exception.Message)",
                "Comparison Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
    else {
        $validationA = Test-NaaccrXmlFile -FilePath $filePathA
        if (-not $validationA.IsValid) {
            [System.Windows.Forms.MessageBox]::Show(
                "First file is not a valid NAACCR XML file:`n`n$($validationA.Error)",
                "Invalid File",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        $validationB = Test-NaaccrXmlFile -FilePath $filePathB
        if (-not $validationB.IsValid) {
            [System.Windows.Forms.MessageBox]::Show(
                "Second file is not a valid NAACCR XML file:`n`n$($validationB.Error)",
                "Invalid File",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        try {
            if ($comparisonMode -eq "Line") {
                Show-XmlFileDiff -FilePathA $filePathA -FilePathB $filePathB
            }
            else {
                $diffResult = Compare-XmlFiles -FilePathA $filePathA -FilePathB $filePathB
                Show-DiffPreview -DiffResult $diffResult -FilePathA $filePathA -FilePathB $filePathB
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error comparing files:`n`n$($_.Exception.Message)",
                "Comparison Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}

function Show-FileDiffSetupDialog {
    <#
    .SYNOPSIS
    Shows a dialog for setting up file diff - file selection and comparison mode.
    Returns hashtable with FilePathA, FilePathB, FileType, ComparisonMode, or $null if cancelled.
    #>

    $setupForm = New-Object System.Windows.Forms.Form
    $setupForm.Text = "Diff Files"
    $setupForm.Width = 600
    $setupForm.Height = 320
    $setupForm.StartPosition = "CenterScreen"
    $setupForm.FormBorderStyle = "FixedDialog"
    $setupForm.MaximizeBox = $false
    $setupForm.MinimizeBox = $false

    $script:detectedFileType = $null

    $lblFileA = New-Object System.Windows.Forms.Label
    $lblFileA.Location = New-Object System.Drawing.Point(15, 20)
    $lblFileA.Size = New-Object System.Drawing.Size(100, 20)
    $lblFileA.Text = "First File:"

    $txtFileA = New-Object System.Windows.Forms.TextBox
    $txtFileA.Location = New-Object System.Drawing.Point(15, 42)
    $txtFileA.Size = New-Object System.Drawing.Size(470, 23)
    $txtFileA.ReadOnly = $true

    $btnBrowseA = New-Object System.Windows.Forms.Button
    $btnBrowseA.Location = New-Object System.Drawing.Point(495, 41)
    $btnBrowseA.Size = New-Object System.Drawing.Size(80, 25)
    $btnBrowseA.Text = "Browse..."

    $lblFileB = New-Object System.Windows.Forms.Label
    $lblFileB.Location = New-Object System.Drawing.Point(15, 75)
    $lblFileB.Size = New-Object System.Drawing.Size(100, 20)
    $lblFileB.Text = "Second File:"

    $txtFileB = New-Object System.Windows.Forms.TextBox
    $txtFileB.Location = New-Object System.Drawing.Point(15, 97)
    $txtFileB.Size = New-Object System.Drawing.Size(470, 23)
    $txtFileB.ReadOnly = $true
    $txtFileB.Enabled = $false

    $btnBrowseB = New-Object System.Windows.Forms.Button
    $btnBrowseB.Location = New-Object System.Drawing.Point(495, 96)
    $btnBrowseB.Size = New-Object System.Drawing.Size(80, 25)
    $btnBrowseB.Text = "Browse..."
    $btnBrowseB.Enabled = $false

    $grpHl7Mode = New-Object System.Windows.Forms.GroupBox
    $grpHl7Mode.Location = New-Object System.Drawing.Point(15, 135)
    $grpHl7Mode.Size = New-Object System.Drawing.Size(560, 75)
    $grpHl7Mode.Text = "HL7 Comparison Method"
    $grpHl7Mode.Visible = $false

    $rbHl7Index = New-Object System.Windows.Forms.RadioButton
    $rbHl7Index.Location = New-Object System.Drawing.Point(15, 22)
    $rbHl7Index.Size = New-Object System.Drawing.Size(530, 20)
    $rbHl7Index.Text = "By Position - compare message 1 vs message 1, message 2 vs message 2, etc."
    $rbHl7Index.Checked = $true

    $rbHl7Key = New-Object System.Windows.Forms.RadioButton
    $rbHl7Key.Location = New-Object System.Drawing.Point(15, 46)
    $rbHl7Key.Size = New-Object System.Drawing.Size(530, 20)
    $rbHl7Key.Text = "By Message Control ID - match messages by MSH-10 identifier"

    $grpHl7Mode.Controls.AddRange(@($rbHl7Index, $rbHl7Key))

    $grpXmlMode = New-Object System.Windows.Forms.GroupBox
    $grpXmlMode.Location = New-Object System.Drawing.Point(15, 135)
    $grpXmlMode.Size = New-Object System.Drawing.Size(560, 75)
    $grpXmlMode.Text = "XML Comparison Method"
    $grpXmlMode.Visible = $false

    $rbXmlLine = New-Object System.Windows.Forms.RadioButton
    $rbXmlLine.Location = New-Object System.Drawing.Point(15, 22)
    $rbXmlLine.Size = New-Object System.Drawing.Size(530, 20)
    $rbXmlLine.Text = "Line-by-Line - traditional diff view (warning: large files are slower)"

    $rbXmlPatient = New-Object System.Windows.Forms.RadioButton
    $rbXmlPatient.Location = New-Object System.Drawing.Point(15, 46)
    $rbXmlPatient.Size = New-Object System.Drawing.Size(530, 20)
    $rbXmlPatient.Text = "By Patient - compare patient records by position"
    $rbXmlPatient.Checked = $true

    $grpXmlMode.Controls.AddRange(@($rbXmlLine, $rbXmlPatient))

    $btnCompare = New-Object System.Windows.Forms.Button
    $btnCompare.Location = New-Object System.Drawing.Point(400, 235)
    $btnCompare.Size = New-Object System.Drawing.Size(90, 28)
    $btnCompare.Text = "Compare"
    $btnCompare.Enabled = $false
    $btnCompare.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(500, 235)
    $btnCancel.Size = New-Object System.Drawing.Size(75, 28)
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $setupForm.AcceptButton = $btnCompare
    $setupForm.CancelButton = $btnCancel

    $btnBrowseA.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Files (*.xml;*.hl7)|*.xml;*.hl7|XML Files (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*"
        $ofd.Title = "Select First File"
        $ofd.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtFileA.Text = $ofd.FileName
            $ext = [System.IO.Path]::GetExtension($ofd.FileName).ToLower()
            if ($ext -eq ".hl7") {
                $script:detectedFileType = "hl7"
                $grpHl7Mode.Visible = $true
                $grpXmlMode.Visible = $false
            }
            elseif ($ext -eq ".xml") {
                $script:detectedFileType = "xml"
                $grpHl7Mode.Visible = $false
                $grpXmlMode.Visible = $true
            }
            else {
                $script:detectedFileType = $null
                $grpHl7Mode.Visible = $false
                $grpXmlMode.Visible = $false
            }

            $txtFileB.Enabled = $true
            $btnBrowseB.Enabled = $true
            $txtFileB.Text = ""
            $btnCompare.Enabled = $false
        }
    })

    $btnBrowseB.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "Select Second File"

        if ($script:detectedFileType -eq "hl7") {
            $ofd.Filter = "HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*"
        }
        elseif ($script:detectedFileType -eq "xml") {
            $ofd.Filter = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
        }
        else {
            $ofd.Filter = "Files (*.xml;*.hl7)|*.xml;*.hl7|All Files (*.*)|*.*"
        }

        if ($txtFileA.Text) {
            $ofd.InitialDirectory = [System.IO.Path]::GetDirectoryName($txtFileA.Text)
        }

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $ext = [System.IO.Path]::GetExtension($ofd.FileName).ToLower()
            $expectedExt = if ($script:detectedFileType -eq "hl7") { ".hl7" } elseif ($script:detectedFileType -eq "xml") { ".xml" } else { $null }

            if ($null -ne $expectedExt -and $ext -ne $expectedExt) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Second file must be the same type as the first file ($expectedExt).",
                    "File Type Mismatch",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }

            $txtFileB.Text = $ofd.FileName
            $btnCompare.Enabled = $true
        }
    })

    $setupForm.Controls.AddRange(@(
        $lblFileA, $txtFileA, $btnBrowseA,
        $lblFileB, $txtFileB, $btnBrowseB,
        $grpHl7Mode, $grpXmlMode,
        $btnCompare, $btnCancel
    ))

    $result = $setupForm.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        if (-not (Test-Path $txtFileA.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "First file does not exist: $($txtFileA.Text)",
                "File Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $null
        }

        if (-not (Test-Path $txtFileB.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Second file does not exist: $($txtFileB.Text)",
                "File Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $null
        }

        $compMode = "Index"
        if ($script:detectedFileType -eq "hl7") {
            $compMode = if ($rbHl7Index.Checked) { "Index" } else { "Key" }
        }
        elseif ($script:detectedFileType -eq "xml") {
            $compMode = if ($rbXmlLine.Checked) { "Line" } else { "Patient" }
        }

        return @{
            FilePathA      = $txtFileA.Text
            FilePathB      = $txtFileB.Text
            FileType       = $script:detectedFileType
            ComparisonMode = $compMode
        }
    }

    return $null
}

function Show-XmlFileDiff {
    param(
        [string]$FilePathA,
        [string]$FilePathB
    )

    $fileNameA = [System.IO.Path]::GetFileName($FilePathA)
    $fileNameB = [System.IO.Path]::GetFileName($FilePathB)

    $linesA = Get-FormattedXmlLines -FilePath $FilePathA
    $linesB = Get-FormattedXmlLines -FilePath $FilePathB
    $diffLines = Get-DiffLines -LinesA $linesA -LinesB $linesB

    $addedCount = ($diffLines | Where-Object { $_.Status -eq 'Added' }).Count
    $deletedCount = ($diffLines | Where-Object { $_.Status -eq 'Deleted' }).Count
    $unchangedCount = ($diffLines | Where-Object { $_.Status -eq 'Unchanged' }).Count

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "File Diff: $fileNameA vs $fileNameB"
    $diffForm.Width = 1400
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 50)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $summaryText = "File A: $fileNameA ($($linesA.Count) lines)  |  File B: $fileNameB ($($linesB.Count) lines)`n"
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

function Test-NaaccrXmlFile {
    param(
        [string]$FilePath
    )

    if ((Get-Item $FilePath).Length -eq 0) {
        return @{
            IsValid = $false
            Error = "File is empty"
        }
    }

    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($FilePath)

        if ($xmlDoc.DocumentElement.LocalName -ne "NaaccrData") {
            return @{
                IsValid = $false
                Error = "Root element is not <NaaccrData>. Found: <$($xmlDoc.DocumentElement.LocalName)>"
            }
        }

        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "XML parsing error: $($_.Exception.Message)"
        }
    }
}

function Test-Hl7File {
    param(
        [string]$FilePath
    )

    if ((Get-Item $FilePath).Length -eq 0) {
        return @{
            IsValid = $false
            Error = "File is empty"
        }
    }

    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        $lineCount = 0
        $foundMsh = $false

        while ($lineCount -lt 5 -and -not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $lineCount++
            if ($line -match "^MSH\|") {
                $foundMsh = $true
                break
            }
        }
        $reader.Close()

        if (-not $foundMsh) {
            return @{
                IsValid = $false
                Error = "No MSH| segment found in first 5 lines. Not a valid HL7 file."
            }
        }

        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "Error reading file: $($_.Exception.Message)"
        }
    }
}

function Get-Hl7MessageHeaders {
    param(
        [string]$FilePath
    )

    $headers = New-Object System.Collections.ArrayList
    $content = Get-Content -Path $FilePath -Raw -Encoding ASCII
    $messages = $content -split "(?m)^MSH\|"
    $messages = $messages | Where-Object { $_ -match '\S' }

    $messageIndex = 0
    foreach ($msg in $messages) {
        $messageIndex++

        if (-not $msg.StartsWith("MSH|")) {
            $msg = "MSH|" + $msg
        }

        $mshMatch = [regex]::Match($msg, "(?m)^MSH\|([^\r\n]+)")
        $mshLine = if ($mshMatch.Success) { $mshMatch.Groups[1].Value } else { "" }

        $pidMatch = [regex]::Match($msg, "(?m)^PID\|([^\r\n]+)")
        $pidLine = if ($pidMatch.Success) { $pidMatch.Groups[1].Value } else { "" }

        # Parse MSH fields (fields are 0-indexed after the initial MSH|)
        # MSH|^~\&|sendApp|sendFac|recvApp|recvFac|datetime|security|messageType|messageControlId|...
        # After split on |: 0=encoding(^~\&), 1=sendApp, 2=sendFac, 3=recvApp, 4=recvFac,
        #                   5=datetime, 6=security, 7=messageType(MSH-9), 8=messageControlId(MSH-10)
        $mshFields = if ($mshLine) { $mshLine -split '\|' } else { @() }
        $messageType = if ($mshFields.Count -gt 7) { $mshFields[7] } else { "" }
        $messageControlId = if ($mshFields.Count -gt 8) { $mshFields[8] } else { "" }

        # Parse PID fields
        # PID|setId|externalId|patientId|altPatientId|patientName|motherMaidenName|dob|...
        # After split: 0=setId, 1=externalId, 2=patientId(PID-3), 3=altPatientId,
        #              4=patientName(PID-5), 5=motherMaidenName, 6=dob(PID-7)
        $pidFields = if ($pidLine) { $pidLine -split '\|' } else { @() }
        $patientId = if ($pidFields.Count -gt 2) { $pidFields[2] } else { "" }
        $patientName = if ($pidFields.Count -gt 4) { $pidFields[4] } else { "" }
        $dob = if ($pidFields.Count -gt 6) { $pidFields[6] } else { "" }

        # Parse patient name (format: LastName^FirstName^MiddleName...)
        $nameParts = $patientName -split '\^'
        $lastName = if ($nameParts.Count -gt 0) { $nameParts[0] } else { "" }
        $firstName = if ($nameParts.Count -gt 1) { $nameParts[1] } else { "" }

        [void]$headers.Add(@{
            MessageIndex     = $messageIndex
            PatientId        = $patientId
            PatientLastName  = $lastName
            PatientFirstName = $firstName
            DateOfBirth      = $dob
            MessageControlId = $messageControlId
            MessageType      = $messageType
            RawMessage       = $msg
        })
    }

    return $headers
}

function Get-Hl7MessageKey {
    param(
        [hashtable]$MessageHeader
    )

    if (-not [string]::IsNullOrWhiteSpace($MessageHeader.MessageControlId)) {
        return $MessageHeader.MessageControlId
    }

    $key = ""
    if (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientId)) {
        $key = $MessageHeader.PatientId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientLastName)) {
        $key = $MessageHeader.PatientLastName
        if (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientFirstName)) {
            $key += "^" + $MessageHeader.PatientFirstName
        }
        if (-not [string]::IsNullOrWhiteSpace($MessageHeader.DateOfBirth)) {
            $key += "^" + $MessageHeader.DateOfBirth
        }
    }

    if ([string]::IsNullOrWhiteSpace($key)) {
        return "MSG-$($MessageHeader.MessageIndex)"
    }

    return "$key-MSG$($MessageHeader.MessageIndex)"
}

function Compare-Hl7Files {
    param(
        [string]$FilePathA,
        [string]$FilePathB,
        [string]$Method = "Index"  # "Index" or "Key"
    )

    $headersA = Get-Hl7MessageHeaders -FilePath $FilePathA
    $headersB = Get-Hl7MessageHeaders -FilePath $FilePathB

    $comparisons = @()

    if ($Method -eq "Index") {
        $maxCount = [Math]::Max($headersA.Count, $headersB.Count)

        for ($i = 0; $i -lt $maxCount; $i++) {
            $msgA = if ($i -lt $headersA.Count) { $headersA[$i] } else { $null }
            $msgB = if ($i -lt $headersB.Count) { $headersB[$i] } else { $null }

            if ($null -ne $msgA -and $null -ne $msgB) {
                $rawA = $msgA.RawMessage -replace '\s+', ' '
                $rawB = $msgB.RawMessage -replace '\s+', ' '
                $isSame = $rawA -eq $rawB

                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = $msgB.PatientId
                    Status         = if ($isSame) { "Same" } else { "Different Content" }
                    InFileA        = $true
                    InFileB        = $true
                    NameA          = $nameA
                    NameB          = $nameB
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = $msgB.MessageType
                }
            }
            elseif ($null -ne $msgA) {
                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = ""
                    Status         = "OnlyInA"
                    InFileA        = $true
                    InFileB        = $false
                    NameA          = $nameA
                    NameB          = ""
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = ""
                }
            }
            else {
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = ""
                    PatientIdB     = $msgB.PatientId
                    Status         = "OnlyInB"
                    InFileA        = $false
                    InFileB        = $true
                    NameA          = ""
                    NameB          = $nameB
                    MessageTypeA   = ""
                    MessageTypeB   = $msgB.MessageType
                }
            }
        }
    }
    else {
        $mapA = @{}
        $mapB = @{}

        foreach ($header in $headersA) {
            $msgKey = Get-Hl7MessageKey -MessageHeader $header
            $mapA[$msgKey] = $header
        }

        foreach ($header in $headersB) {
            $msgKey = Get-Hl7MessageKey -MessageHeader $header
            $mapB[$msgKey] = $header
        }

        $allMessageKeys = New-Object System.Collections.Generic.HashSet[string]
        foreach ($key in $mapA.Keys) { [void]$allMessageKeys.Add($key) }
        foreach ($key in $mapB.Keys) { [void]$allMessageKeys.Add($key) }

        foreach ($msgKey in $allMessageKeys) {
            $inA = $mapA.ContainsKey($msgKey)
            $inB = $mapB.ContainsKey($msgKey)

            if ($inA -and $inB) {
                $msgA = $mapA[$msgKey]
                $msgB = $mapB[$msgKey]

                $rawA = $msgA.RawMessage -replace '\s+', ' '
                $rawB = $msgB.RawMessage -replace '\s+', ' '
                $isSame = $rawA -eq $rawB

                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgA.MessageIndex
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = $msgB.PatientId
                    Status         = if ($isSame) { "Same" } else { "Different Content" }
                    InFileA        = $true
                    InFileB        = $true
                    NameA          = $nameA
                    NameB          = $nameB
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = $msgB.MessageType
                }
            }
            elseif ($inA) {
                $msgA = $mapA[$msgKey]
                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgA.MessageIndex
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = ""
                    Status         = "OnlyInA"
                    InFileA        = $true
                    InFileB        = $false
                    NameA          = $nameA
                    NameB          = ""
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = ""
                }
            }
            else {
                $msgB = $mapB[$msgKey]
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgB.MessageIndex
                    PatientIdA     = ""
                    PatientIdB     = $msgB.PatientId
                    Status         = "OnlyInB"
                    InFileA        = $false
                    InFileB        = $true
                    NameA          = ""
                    NameB          = $nameB
                    MessageTypeA   = ""
                    MessageTypeB   = $msgB.MessageType
                }
            }
        }
    }

    $comparisons = $comparisons | Sort-Object { $_.Index }

    $stats = @{
        TotalMessagesA = $headersA.Count
        TotalMessagesB = $headersB.Count
        Same           = ($comparisons | Where-Object { $_.Status -eq "Same" }).Count
        Different      = ($comparisons | Where-Object { $_.Status -eq "Different Content" }).Count
        OnlyInA        = ($comparisons | Where-Object { $_.Status -eq "OnlyInA" }).Count
        OnlyInB        = ($comparisons | Where-Object { $_.Status -eq "OnlyInB" }).Count
    }

    return @{
        Comparisons = $comparisons
        Stats       = $stats
        Method      = $Method
    }
}

function Show-Hl7FileDiffPreview {
    param(
        [hashtable]$DiffResult,
        [string]$FilePathA,
        [string]$FilePathB
    )

    $fileNameA = [System.IO.Path]::GetFileName($FilePathA)
    $fileNameB = [System.IO.Path]::GetFileName($FilePathB)

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "HL7 File Diff: $fileNameA vs $fileNameB"
    $diffForm.Width = 1600
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"

    $stats = $DiffResult.Stats
    $method = if ($DiffResult.Method -eq "Index") { "By Position" } else { "By Message Control ID" }
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 60)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    $fileNameA = [System.IO.Path]::GetDirectoryName($FilePathA) + "\" + $fileNameA
    $fileNameB = [System.IO.Path]::GetDirectoryName($FilePathB) + "\" + $fileNameB

    $summaryText = "A. $fileNameA ($($stats.TotalMessagesA) messages)  |  B. $fileNameB ($($stats.TotalMessagesB) messages)  |  Method: $method`n"
    $summaryText += "Results: $($stats.Same) same, $($stats.Different) different content, $($stats.OnlyInA) only in A, $($stats.OnlyInB) only in B"
    $lblSummary.Text = $summaryText

    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Location = New-Object System.Drawing.Point(10, 80)
    $gridDiff.Size = New-Object System.Drawing.Size(1560, 750)
    $gridDiff.Anchor = 'Top,Left,Right,Bottom'
    $gridDiff.ReadOnly = $true
    $gridDiff.AllowUserToAddRows = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.RowHeadersVisible = $false
    $gridDiff.SelectionMode = 'FullRowSelect'
    $gridDiff.MultiSelect = $false
    $gridDiff.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("#", [int])
    [void]$table.Columns.Add("Status", [string])
    [void]$table.Columns.Add("PatientID_A", [string])
    [void]$table.Columns.Add("PatientID_B", [string])
    [void]$table.Columns.Add("NameA", [string])
    [void]$table.Columns.Add("NameB", [string])
    [void]$table.Columns.Add("TypeA", [string])
    [void]$table.Columns.Add("TypeB", [string])

    foreach ($comp in $DiffResult.Comparisons) {
        $row = $table.NewRow()

        $row["#"] = $comp.Index
        $row["Status"] = switch ($comp.Status) {
            "Same" { "Same" }
            "Different Content" { "Different Content" }
            "OnlyInA" { "Only in A" }
            "OnlyInB" { "Only in B" }
        }

        $row["PatientID_A"] = $comp.PatientIdA
        $row["PatientID_B"] = $comp.PatientIdB
        $row["NameA"] = $comp.NameA
        $row["NameB"] = $comp.NameB
        $row["TypeA"] = $comp.MessageTypeA
        $row["TypeB"] = $comp.MessageTypeB

        [void]$table.Rows.Add($row)
    }

    $gridDiff.DataSource = $table

    if ($gridDiff.Columns.Count -ge 8) {
        $gridDiff.Columns[0].Width = 40
        $gridDiff.Columns[1].Width = 90
        $gridDiff.Columns[2].Width = 120
        $gridDiff.Columns[3].Width = 120
        $gridDiff.Columns[4].AutoSizeMode = 'Fill'
        $gridDiff.Columns[5].AutoSizeMode = 'Fill'
        $gridDiff.Columns[6].Width = 100
        $gridDiff.Columns[7].Width = 100
    }

    $gridDiff.add_RowPrePaint({
        param($grid, $e)
        $row = $grid.Rows[$e.RowIndex]
        $status = [string]$row.Cells[1].Value

        switch ($status) {
            "Same" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen
            }
            "Different Content" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCoral
            }
            "Only in A" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightBlue
            }
            "Only in B" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightSteelBlue
            }
        }
    })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1470, 840)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({
        $diffForm.Close()
    })

    $diffForm.Controls.AddRange(@($lblSummary, $gridDiff, $btnClose))

    [void]$diffForm.ShowDialog()
}

function Compare-XmlFiles {
    param(
        [string]$FilePathA,
        [string]$FilePathB
    )

    $xmlDocA = New-Object System.Xml.XmlDocument
    $xmlDocA.Load($FilePathA)

    $xmlDocB = New-Object System.Xml.XmlDocument
    $xmlDocB.Load($FilePathB)

    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDocA.NameTable)
    $nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml")

    $patientsA = $xmlDocA.SelectNodes("//n:Patient", $nsMgr)
    $patientsB = $xmlDocB.SelectNodes("//n:Patient", $nsMgr)

    $comparisons = @()
    $maxCount = [Math]::Max($patientsA.Count, $patientsB.Count)

    for ($i = 0; $i -lt $maxCount; $i++) {
        $patientA = if ($i -lt $patientsA.Count) { $patientsA[$i] } else { $null }
        $patientB = if ($i -lt $patientsB.Count) { $patientsB[$i] } else { $null }

        if ($null -ne $patientA -and $null -ne $patientB) {
            $isSame = Compare-PatientRecords -PatientA $patientA -PatientB $patientB -NsMgr $nsMgr

            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = if ($isSame) { "Same" } else { "Different Content" }
                InFileA = $true
                InFileB = $true
                PatientA = $patientA
                PatientB = $patientB
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
        elseif ($null -ne $patientA) {
            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = "OnlyInA"
                InFileA = $true
                InFileB = $false
                PatientA = $patientA
                PatientB = $null
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = ""
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = 0
            }
        }
        else {
            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = "OnlyInB"
                InFileA = $false
                InFileB = $true
                PatientA = $null
                PatientB = $patientB
                NameA = ""
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = 0
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
    }

    $stats = @{
        TotalPatientsA = $patientsA.Count
        TotalPatientsB = $patientsB.Count
        Same = ($comparisons | Where-Object { $_.Status -eq "Same" }).Count
        Different = ($comparisons | Where-Object { $_.Status -eq "Different Content" }).Count
        OnlyInA = ($comparisons | Where-Object { $_.Status -eq "OnlyInA" }).Count
        OnlyInB = ($comparisons | Where-Object { $_.Status -eq "OnlyInB" }).Count
    }

    return @{
        Comparisons = $comparisons
        Stats = $stats
        NsMgr = $nsMgr
    }
}

function Get-PatientKey {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    # Use name + DOB as key (patientIdNumber is just a file-specific sequence number)
    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
    $dob = $Patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $NsMgr)

    $key = ""
    if ($lastName) { $key += $lastName.InnerText }
    if ($firstName) { $key += "|" + $firstName.InnerText }
    if ($dob) { $key += "|" + $dob.InnerText }

    if (-not [string]::IsNullOrWhiteSpace($key)) {
        return $key
    }

    $patientIdNode = $Patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $NsMgr)
    if ($null -ne $patientIdNode -and -not [string]::IsNullOrWhiteSpace($patientIdNode.InnerText)) {
        return $patientIdNode.InnerText
    }

    return [guid]::NewGuid().ToString()
}

function Get-PatientName {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )
    
    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
    
    $name = ""
    if ($lastName) { $name = $lastName.InnerText }
    if ($firstName) { 
        if ($name) { $name += ", " }
        $name += $firstName.InnerText 
    }
    
    return $name
}

function Compare-PatientRecords {
    param(
        [System.Xml.XmlElement]$PatientA,
        [System.Xml.XmlElement]$PatientB,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $linesA = Get-FormattedPatientXml -Patient $PatientA
    $linesB = Get-FormattedPatientXml -Patient $PatientB

    if ($linesA.Count -ne $linesB.Count) {
        return $false
    }

    for ($i = 0; $i -lt $linesA.Count; $i++) {
        if ($linesA[$i] -ne $linesB[$i]) {
            return $false
        }
    }

    return $true
}

function Get-FormattedPatientXml {
    param(
        [System.Xml.XmlElement]$Patient
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`n"
    $settings.OmitXmlDeclaration = $true

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $Patient.WriteTo($xw)
    $xw.Flush()
    $xw.Close()

    $formatted = $sw.ToString()
    $sw.Close()

    $lines = @($formatted -split "`n" | ForEach-Object { $_.TrimEnd("`r", " ") })
    return $lines
}

function Get-FormattedXmlLines {
    param(
        [string]$FilePath
    )
    
    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.PreserveWhitespace = $false
        $xmlDoc.Load($FilePath)
        
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.IndentChars = "  "
        $settings.NewLineChars = "`n"
        $settings.NewLineHandling = "Replace"
        $settings.OmitXmlDeclaration = $false
        
        $sw = New-Object System.IO.StringWriter
        $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
        $xmlDoc.Save($xw)
        $xw.Flush()
        $xw.Close()
        
        $formattedXml = $sw.ToString()
        $sw.Close()

        $lines = @($formattedXml -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
        
        return ,$lines
    }
    catch {
        throw "Error formatting XML: $($_.Exception.Message)"
    }
}

function Show-DiffPreview {
    param(
        [hashtable]$DiffResult,
        [string]$FilePathA,
        [string]$FilePathB
    )
    
    $fileNameA = [System.IO.Path]::GetFileName($FilePathA)
    $fileNameB = [System.IO.Path]::GetFileName($FilePathB)
    
    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "File Diff: $fileNameA vs $fileNameB"
    $diffForm.Width = 1600
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"
    
    $stats = $DiffResult.Stats
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 60)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    $summaryText = "File A: $fileNameA ($($stats.TotalPatientsA) patients)`n"
    $summaryText += "File B: $fileNameB ($($stats.TotalPatientsB) patients)`n"
    $summaryText += "Results: $($stats.Same) same, $($stats.Different) different content, $($stats.OnlyInA) only in A, $($stats.OnlyInB) only in B"
    $lblSummary.Text = $summaryText
    
    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Location = New-Object System.Drawing.Point(10, 80)
    $gridDiff.Size = New-Object System.Drawing.Size(1560, 750)
    $gridDiff.Anchor = 'Top,Left,Right,Bottom'
    $gridDiff.ReadOnly = $true
    $gridDiff.AllowUserToAddRows = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.RowHeadersVisible = $false
    $gridDiff.SelectionMode = 'FullRowSelect'
    $gridDiff.MultiSelect = $false
    $gridDiff.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Status", [string])
    [void]$table.Columns.Add("PatientID", [string])
    [void]$table.Columns.Add("NameA", [string])
    [void]$table.Columns.Add("NameB", [string])
    [void]$table.Columns.Add("TumorsA", [int])
    [void]$table.Columns.Add("TumorsB", [int])
    
    foreach ($comp in $DiffResult.Comparisons) {
        $row = $table.NewRow()
        
        $row["Status"] = switch ($comp.Status) {
            "Same" { "Same" }
            "Different Content" { "Different Content" }
            "OnlyInA" { "Only in A" }
            "OnlyInB" { "Only in B" }
        }
        
        $row["PatientID"] = $comp.PatientId
        $row["NameA"] = $comp.NameA
        $row["NameB"] = $comp.NameB
        $row["TumorsA"] = $comp.TumorCountA
        $row["TumorsB"] = $comp.TumorCountB
        
        [void]$table.Rows.Add($row)
    }
    
    $gridDiff.DataSource = $table

    if ($gridDiff.Columns.Count -ge 6) {
        $col0 = $gridDiff.Columns[0]
        $col1 = $gridDiff.Columns[1]
        $col2 = $gridDiff.Columns[2]
        $col3 = $gridDiff.Columns[3]
        $col4 = $gridDiff.Columns[4]
        $col5 = $gridDiff.Columns[5]
        
        if ($null -ne $col0) { $col0.Width = 100 }
        if ($null -ne $col1) { $col1.Width = 150 }
        if ($null -ne $col2) { $col2.AutoSizeMode = 'Fill' }
        if ($null -ne $col3) { $col3.AutoSizeMode = 'Fill' }
        if ($null -ne $col4) { $col4.Width = 80 }
        if ($null -ne $col5) { $col5.Width = 80 }
    }

    $gridDiff.add_RowPrePaint({
        param($grid, $e)
        $row = $grid.Rows[$e.RowIndex]
        $status = [string]$row.Cells[0].Value

        switch ($status) {
            "Same" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen
            }
            "Different Content" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCoral
            }
            "Only in A" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightBlue
            }
            "Only in B" {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightSteelBlue
            }
        }
    })

    $script:xmlComparisons = $DiffResult.Comparisons
    $script:xmlNsMgr = $DiffResult.NsMgr

    $gridDiff.Add_CellDoubleClick({
        param($gridSender, $e)
        $rowIndex = $e.RowIndex
        if ($rowIndex -lt 0) { return }

        $comp = $script:xmlComparisons[$rowIndex]
        if ($null -eq $comp) { return }

        Show-PatientDetailedDiff -Comparison $comp -NsMgr $script:xmlNsMgr
    })

    $lblInstruction = New-Object System.Windows.Forms.Label
    $lblInstruction.Location = New-Object System.Drawing.Point(10, 840)
    $lblInstruction.Size = New-Object System.Drawing.Size(400, 25)
    $lblInstruction.Text = "Double-click a row to view detailed diff"
    $lblInstruction.ForeColor = [System.Drawing.Color]::Gray
    $lblInstruction.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1470, 840)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({
        $diffForm.Close()
    })

    $diffForm.Controls.AddRange(@($lblSummary, $gridDiff, $lblInstruction, $btnClose))

    [void]$diffForm.ShowDialog()

    $script:xmlComparisons = $null
    $script:xmlNsMgr = $null
}

function Show-PatientDetailedDiff {
    param(
        [hashtable]$Comparison,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $patientA = $Comparison.PatientA
    $patientB = $Comparison.PatientB

    $linesA = if ($null -ne $patientA) { Get-FormattedPatientXml -Patient $patientA } else { @() }
    $linesB = if ($null -ne $patientB) { Get-FormattedPatientXml -Patient $patientB } else { @() }
    $diffLines = Get-DiffLines -LinesA $linesA -LinesB $linesB

    $detailForm = New-Object System.Windows.Forms.Form
    $detailForm.Text = "Detailed Diff - Patient $($Comparison.PatientId)"
    $detailForm.Width = 1400
    $detailForm.Height = 800
    $detailForm.StartPosition = "CenterScreen"

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSummary.Text = "File A: $($Comparison.NameA) ($($linesA.Count) lines)  |  File B: $($Comparison.NameB) ($($linesB.Count) lines)"

    $rtbDiff = New-Object System.Windows.Forms.RichTextBox
    $rtbDiff.Location = New-Object System.Drawing.Point(10, 55)
    $rtbDiff.Size = New-Object System.Drawing.Size(1360, 660)
    $rtbDiff.Anchor = 'Top,Left,Right,Bottom'
    $rtbDiff.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbDiff.ReadOnly = $true
    $rtbDiff.WordWrap = $false
    $rtbDiff.ScrollBars = 'Both'

    foreach ($line in $diffLines) {
        $prefix = ""
        $color = [System.Drawing.Color]::Black
        $bgColor = [System.Drawing.Color]::White

        switch ($line.Status) {
            'Unchanged' {
                $prefix = "  "
                $color = [System.Drawing.Color]::Black
                $bgColor = [System.Drawing.Color]::White
            }
            'Added' {
                $prefix = "+ "
                $color = [System.Drawing.Color]::DarkGreen
                $bgColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
            }
            'Deleted' {
                $prefix = "- "
                $color = [System.Drawing.Color]::DarkRed
                $bgColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
            }
        }

        $content = if ($line.Status -eq 'Added') { $line.ContentB } else { $line.ContentA }
        $text = "$prefix$content`n"

        $rtbDiff.SelectionStart = $rtbDiff.TextLength
        $rtbDiff.SelectionLength = 0
        $rtbDiff.SelectionColor = $color
        $rtbDiff.SelectionBackColor = $bgColor
        $rtbDiff.AppendText($text)
    }

    $rtbDiff.SelectionStart = 0
    $rtbDiff.ScrollToCaret()

    $lblLegend = New-Object System.Windows.Forms.Label
    $lblLegend.Location = New-Object System.Drawing.Point(10, 725)
    $lblLegend.Size = New-Object System.Drawing.Size(600, 20)
    $lblLegend.Text = "Legend:  + Added (in B only)  |  - Removed (in A only)  |  (no prefix) Unchanged"
    $lblLegend.ForeColor = [System.Drawing.Color]::Gray
    $lblLegend.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1280, 720)
    $btnClose.Size = New-Object System.Drawing.Size(90, 28)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ $detailForm.Close() })

    $detailForm.Controls.AddRange(@($lblSummary, $rtbDiff, $lblLegend, $btnClose))
    [void]$detailForm.ShowDialog()
}
