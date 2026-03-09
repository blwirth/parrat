# hl7-viewer.ps1
# HL7 message display functions

function Show-Hl7Message {
    param(
        [int]$Index,
        [array]$Messages = $null,
        [hashtable]$Controls = $null
    )

    # Use passed parameters or fall back to script-scope variables
    if ($null -eq $Messages) {
        $Messages = $script:Hl7Messages
    }
    if ($null -eq $Controls) {
        $Controls = $script:Controls
    }

    if ($null -eq $Messages -or $Messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No HL7 messages loaded!", "Error")
        return
    }
    if ($Index -lt 0 -or $Index -ge $Messages.Count) {
        [System.Windows.Forms.MessageBox]::Show("Index out of range! Index: $Index, Count: $($Messages.Count)", "Error")
        return
    }

    $script:CurrentIndex = $Index
    $message = $Messages[$Index]

    $rtbPath = $Controls['rtbPath']
    $rtbItems = $Controls['rtbItems']
    $lblIndex = $Controls['lblIndex']
    $btnPrev = $Controls['btnPrev']
    $btnNext = $Controls['btnNext']
    $gridNav = $Controls['gridNav']

    $rtbPath.Clear()
    $rtbItems.Clear()

    # Select the corresponding row in the grid based on the Index column value
    $targetIndexValue = $Index + 1
    $gridNav.ClearSelection()
    foreach ($row in $gridNav.Rows) {
        if ($row.Cells["Index"].Value -eq $targetIndexValue) {
            $row.Selected = $true
            $gridNav.CurrentCell = $row.Cells[0]
            break
        }
    }

    # === MIDDLE PANEL: Clean OBX Text Content ===
    Add-LineToRichTextBox $rtbPath ("=== PATHOLOGY REPORT TEXT ===") $true
    Add-LineToRichTextBox $rtbPath ""

    if ($message.Segments.ContainsKey("OBX")) {
        $cleanText = Get-ObxTextContent -ObxSegments $message.Segments["OBX"]
        if (-not [string]::IsNullOrWhiteSpace($cleanText)) {
            $lines = $cleanText -split "(?:`r`n|`n|`r)"
            foreach ($line in $lines) {
                Add-LineToRichTextBox $rtbPath $line
            }
        }
        else {
            Add-LineToRichTextBox $rtbPath "(No text content in OBX segments)"
        }
    }
    else {
        Add-LineToRichTextBox $rtbPath "(No OBX segments in this message)"
    }

    # === RIGHT PANEL: Raw HL7 Segments + Metadata ===
    Add-LineToRichTextBox $rtbItems ("Message {0} of {1}" -f ($Index + 1), $Messages.Count) $true
    Add-LineToRichTextBox $rtbItems ""

    Add-LineToRichTextBox $rtbItems "=== MESSAGE INFO ===" $true
    Add-LineToRichTextBox $rtbItems ("Message Type: {0}" -f $message.MessageType) $true
    Add-LineToRichTextBox $rtbItems ("Date/Time: {0}" -f (Format-Hl7DateTime $message.MessageDateTime))
    Add-LineToRichTextBox $rtbItems ("Sending App: {0}" -f $message.SendingApplication)
    Add-LineToRichTextBox $rtbItems ("Sending Facility: {0}" -f $message.SendingFacility)
    Add-LineToRichTextBox $rtbItems ""

    Add-LineToRichTextBox $rtbItems "=== PATIENT INFO ===" $true
    Add-LineToRichTextBox $rtbItems ("Patient ID: {0}" -f $message.PatientId) $true
    Add-LineToRichTextBox $rtbItems ("Name: {0}" -f $message.PatientName) $true
    Add-LineToRichTextBox $rtbItems ("Last Name: {0}" -f $message.PatientLastName)
    Add-LineToRichTextBox $rtbItems ("First Name: {0}" -f $message.PatientFirstName)
    Add-LineToRichTextBox $rtbItems ("Date of Birth: {0}" -f (Format-Hl7DateTime $message.DateOfBirth)) $true
    Add-LineToRichTextBox $rtbItems ("Sex: {0}" -f $message.Sex)
    Add-LineToRichTextBox $rtbItems ""

    if (-not [string]::IsNullOrWhiteSpace($message.OrderDateTime) -or
        -not [string]::IsNullOrWhiteSpace($message.OrderingProvider)) {
        Add-LineToRichTextBox $rtbItems "=== ORDER INFO ===" $true
        Add-LineToRichTextBox $rtbItems ("Order Date/Time: {0}" -f (Format-Hl7DateTime $message.OrderDateTime))
        Add-LineToRichTextBox $rtbItems ("Ordering Provider: {0}" -f $message.OrderingProvider)
        Add-LineToRichTextBox $rtbItems ""
    }

    # Notes (NTE segments)
    if ($message.Segments.ContainsKey("NTE")) {
        Add-LineToRichTextBox $rtbItems "=== NOTES ===" $true
        foreach ($nte in $message.Segments["NTE"]) {
            $fields = $nte -split '\|'
            # NTE-3 is the comment text
            $noteText = if ($fields.Count -gt 3) { $fields[3] } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($noteText)) {
                Add-LineToRichTextBox $rtbItems $noteText
            }
        }
        Add-LineToRichTextBox $rtbItems ""
    }

    Add-LineToRichTextBox $rtbItems "=== RAW HL7 SEGMENTS ===" $true
    Add-LineToRichTextBox $rtbItems ""

    $segmentOrder = @("MSH", "PID", "PV1", "ORC", "OBR", "NTE", "OBX")
    $displayedTypes = @()

    foreach ($segType in $segmentOrder) {
        if ($message.Segments.ContainsKey($segType)) {
            Add-LineToRichTextBox $rtbItems ("--- $segType Segment(s) ---") $true
            foreach ($seg in $message.Segments[$segType]) {
                $formattedSeg = Format-Hl7SegmentForDisplay -Segment $seg
                Add-LineToRichTextBox $rtbItems $formattedSeg
            }
            Add-LineToRichTextBox $rtbItems ""
            $displayedTypes += $segType
        }
    }

    # Display any other segment types not in the standard order
    foreach ($segType in $message.Segments.Keys) {
        if ($displayedTypes -notcontains $segType) {
            Add-LineToRichTextBox $rtbItems ("--- $segType Segment(s) ---") $true
            foreach ($seg in $message.Segments[$segType]) {
                $formattedSeg = Format-Hl7SegmentForDisplay -Segment $seg
                Add-LineToRichTextBox $rtbItems $formattedSeg
            }
            Add-LineToRichTextBox $rtbItems ""
        }
    }

    $rtbText = $rtbItems.Text
    $rawSectionMarker = "=== RAW HL7 SEGMENTS ==="
    $rawSectionStart = $rtbText.IndexOf($rawSectionMarker)
    if ($rawSectionStart -ge 0) {
        Set-Hl7PanelHighlighting -RichTextBox $rtbItems -StartOffset ($rawSectionStart + $rawSectionMarker.Length)
    }

    $txtSearch = $Controls['txtSearch']
    if ($null -ne $txtSearch) {
        $searchText = $txtSearch.Text
        Invoke-SearchHighlight -RichTextBox $rtbPath -SearchText $searchText
        Invoke-SearchHighlight -RichTextBox $rtbItems -SearchText $searchText
    }

    $dataTable = $gridNav.DataSource
    $selectedCount = if ($null -ne $dataTable) { @($dataTable.Rows | Where-Object { $_["Selected"] -eq $true }).Count } else { 0 }
    $lblIndex.Text = "Message {0} of {1} ({2} selected)" -f ($Index + 1), $Messages.Count, $selectedCount
    $btnPrev.Enabled = ($Index -gt 0)
    $btnNext.Enabled = ($Index -lt ($Messages.Count - 1))
}

function Format-Hl7SegmentForDisplay {
    param(
        [string]$Segment
    )

    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return ""
    }

    $fields = $Segment -split '\|'
    $segType = $fields[0]

    $result = "$segType"
    for ($i = 1; $i -lt $fields.Count; $i++) {
        $fieldValue = $fields[$i]
        if (-not [string]::IsNullOrWhiteSpace($fieldValue)) {
            $result += "|$fieldValue"
        }
        else {
            $result += "|"
        }
    }

    return $result
}

function Show-RawHl7ForMessage {
    param(
        [int]$Index
    )

    $messages = $script:Hl7Messages

    if ($null -eq $messages -or $messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Show HL7")
        return
    }
    if ($Index -lt 0 -or $Index -ge $messages.Count) {
        [System.Windows.Forms.MessageBox]::Show("Index out of range.", "Show HL7")
        return
    }

    $message = $messages[$Index]
    $rawContent = $message.RawContent

    $label = "Message {0} - {1} ({2})" -f ($Index + 1), $message.PatientName, $message.MessageType

    $hl7Form = New-Object System.Windows.Forms.Form
    $hl7Form.Text = "Raw HL7 - $label"
    $hl7Form.Width = 1400
    $hl7Form.Height = 900
    $hl7Form.StartPosition = "CenterScreen"

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = 'Fill'
    $rtb.ReadOnly = $true
    $rtb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtb.WordWrap = $false
    $rtb.ScrollBars = "Both"

    Set-Hl7SyntaxHighlighting -RichTextBox $rtb -Hl7Text $rawContent

    $hl7Form.Controls.Add($rtb)
    [void]$hl7Form.ShowDialog()
}

