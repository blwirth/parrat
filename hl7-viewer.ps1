# hl7-viewer.ps1
# HL7 message display functions

function Show-Hl7Message {
    param(
        [int]$Index
    )

    if ($script:Hl7Messages.Count -eq 0) { return }
    if ($Index -lt 0 -or $Index -ge $script:Hl7Messages.Count) { return }

    $script:CurrentIndex = $Index
    $script:ScriptVars['CurrentIndex'] = $Index
    $message = $script:Hl7Messages[$Index]

    # Get UI controls
    $rtbPath = $script:Controls['rtbPath']
    $rtbItems = $script:Controls['rtbItems']
    $lblIndex = $script:Controls['lblIndex']
    $btnPrev = $script:Controls['btnPrev']
    $btnNext = $script:Controls['btnNext']
    $gridNav = $script:Controls['gridNav']

    # Clear text boxes
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

    # === MIDDLE PANEL: Raw HL7 Segments ===
    Add-LineToRichTextBox $rtbPath ("=== RAW HL7 MESSAGE ===" ) $true
    Add-LineToRichTextBox $rtbPath ""

    # Display segments grouped by type
    $segmentOrder = @("MSH", "PID", "PV1", "ORC", "OBR", "NTE", "OBX")
    $displayedTypes = @()

    foreach ($segType in $segmentOrder) {
        if ($message.Segments.ContainsKey($segType)) {
            Add-LineToRichTextBox $rtbPath ("--- $segType Segment(s) ---") $true
            foreach ($seg in $message.Segments[$segType]) {
                # Format segment with field separators visible
                $formattedSeg = Format-Hl7SegmentForDisplay -Segment $seg
                Add-LineToRichTextBox $rtbPath $formattedSeg
            }
            Add-LineToRichTextBox $rtbPath ""
            $displayedTypes += $segType
        }
    }

    # Display any other segment types not in the standard order
    foreach ($segType in $message.Segments.Keys) {
        if ($displayedTypes -notcontains $segType) {
            Add-LineToRichTextBox $rtbPath ("--- $segType Segment(s) ---") $true
            foreach ($seg in $message.Segments[$segType]) {
                $formattedSeg = Format-Hl7SegmentForDisplay -Segment $seg
                Add-LineToRichTextBox $rtbPath $formattedSeg
            }
            Add-LineToRichTextBox $rtbPath ""
        }
    }

    # === RIGHT PANEL: Parsed Fields ===
    Add-LineToRichTextBox $rtbItems ("Message {0} of {1}" -f ($Index + 1), $script:Hl7Messages.Count) $true
    Add-LineToRichTextBox $rtbItems ""

    # Message Header Info
    Add-LineToRichTextBox $rtbItems "=== MESSAGE INFO ===" $true
    Add-LineToRichTextBox $rtbItems ("Message Type: {0}" -f $message.MessageType) $true
    Add-LineToRichTextBox $rtbItems ("Date/Time: {0}" -f (Format-Hl7DateTime $message.MessageDateTime))
    Add-LineToRichTextBox $rtbItems ("Sending App: {0}" -f $message.SendingApplication)
    Add-LineToRichTextBox $rtbItems ("Sending Facility: {0}" -f $message.SendingFacility)
    Add-LineToRichTextBox $rtbItems ""

    # Patient Info
    Add-LineToRichTextBox $rtbItems "=== PATIENT INFO ===" $true
    Add-LineToRichTextBox $rtbItems ("Patient ID: {0}" -f $message.PatientId) $true
    Add-LineToRichTextBox $rtbItems ("Name: {0}" -f $message.PatientName) $true
    Add-LineToRichTextBox $rtbItems ("Last Name: {0}" -f $message.PatientLastName)
    Add-LineToRichTextBox $rtbItems ("First Name: {0}" -f $message.PatientFirstName)
    Add-LineToRichTextBox $rtbItems ("Date of Birth: {0}" -f (Format-Hl7DateTime $message.DateOfBirth)) $true
    Add-LineToRichTextBox $rtbItems ("Sex: {0}" -f $message.Sex)
    Add-LineToRichTextBox $rtbItems ""

    # Order Info
    if (-not [string]::IsNullOrWhiteSpace($message.OrderDateTime) -or 
        -not [string]::IsNullOrWhiteSpace($message.OrderingProvider)) {
        Add-LineToRichTextBox $rtbItems "=== ORDER INFO ===" $true
        Add-LineToRichTextBox $rtbItems ("Order Date/Time: {0}" -f (Format-Hl7DateTime $message.OrderDateTime))
        Add-LineToRichTextBox $rtbItems ("Ordering Provider: {0}" -f $message.OrderingProvider)
        Add-LineToRichTextBox $rtbItems ""
    }

    # Observations (OBX segments)
    if ($message.Segments.ContainsKey("OBX")) {
        $observations = Parse-ObxSegments -ObxSegments $message.Segments["OBX"]
        
        if ($observations.Count -gt 0) {
            Add-LineToRichTextBox $rtbItems "=== OBSERVATIONS ===" $true
            
            foreach ($obs in $observations) {
                $obsLine = "{0}: {1}" -f $obs.ObservationId, $obs.ObservationValue
                
                if (-not [string]::IsNullOrWhiteSpace($obs.Units)) {
                    $obsLine += " $($obs.Units)"
                }
                if (-not [string]::IsNullOrWhiteSpace($obs.ReferenceRange)) {
                    $obsLine += " (Ref: $($obs.ReferenceRange))"
                }
                if (-not [string]::IsNullOrWhiteSpace($obs.AbnormalFlag)) {
                    $obsLine += " [$($obs.AbnormalFlag)]"
                    Add-LineToRichTextBox $rtbItems $obsLine $true
                }
                else {
                    Add-LineToRichTextBox $rtbItems $obsLine
                }
            }
            Add-LineToRichTextBox $rtbItems ""
        }
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

    # Update navigation
    $lblIndex.Text = "Message {0} of {1}" -f ($Index + 1), $script:Hl7Messages.Count
    $btnPrev.Enabled = ($Index -gt 0)
    $btnNext.Enabled = ($Index -lt ($script:Hl7Messages.Count - 1))
}

function Format-Hl7SegmentForDisplay {
    param(
        [string]$Segment
    )

    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return ""
    }

    # Split into fields and format with field numbers for readability
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

    if ($script:Hl7Messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No HL7 file loaded.", "Show HL7")
        return
    }
    if ($Index -lt 0 -or $Index -ge $script:Hl7Messages.Count) {
        [System.Windows.Forms.MessageBox]::Show("Index out of range.", "Show HL7")
        return
    }

    $message = $script:Hl7Messages[$Index]
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

    $rtb.Text = $rawContent

    $hl7Form.Controls.Add($rtb)
    [void]$hl7Form.ShowDialog()
}

