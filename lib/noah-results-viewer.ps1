# noah-results-viewer.ps1
# Display NOAH reportability results with color-coded entity highlighting

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Map OBXSegment numbers to OBXTexts keys
# Based on NOAH's segment indices as shown in NLP Options
$script:OBXSegmentMap = @{
    0 = "ClinicalHistory"
    1 = "TextDiagnosis"
    2 = "FinalDiagnosis"
    3 = "GrossPathology"
    4 = "MicroPathology"
    5 = "Comment"
    6 = "NatureOfSpecimen"
    7 = "Supplemental"
    8 = "Addendum"
}

# Entity type colors
$script:EntityColors = @{
    Negated = [System.Drawing.Color]::LightBlue
    Type0   = [System.Drawing.Color]::FromArgb(255, 200, 200)  # Light red/pink (cancer terms)
    Type1   = [System.Drawing.Color]::FromArgb(255, 220, 180)  # Light orange (cytology terms)
    Type2   = [System.Drawing.Color]::FromArgb(220, 200, 255)  # Light purple (site terms)
}

function Get-NoahResultFile {
    param(
        [Parameter(Mandatory=$true)][string]$ReportsFolder
    )

    if (-not (Test-Path -LiteralPath $ReportsFolder)) {
        return $null
    }

    # Look for *_result.json files in the reports folder
    $resultFiles = @(Get-ChildItem -LiteralPath $ReportsFolder -Filter "*_result.json" -File -ErrorAction SilentlyContinue)
    
    if ($resultFiles.Count -eq 0) {
        return $null
    }

    # Return the first (should typically only be one per run)
    return $resultFiles[0].FullName
}

function Show-NoahResultsWindow {
    param(
        [Parameter(Mandatory=$true)][string]$ResultFilePath,
        [Parameter(Mandatory=$true)][string]$WorkingFolder,
        [string]$RecordLabel = "Record",
        [int]$RecordIndex = 0,
        [int]$RecordCount = 1
    )

    if (-not (Test-Path -LiteralPath $ResultFilePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Result file not found:`n$ResultFilePath",
            "NOAH Results",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    # Parse the result JSON
    try {
        $resultJson = Get-Content -LiteralPath $ResultFilePath -Raw | ConvertFrom-Json
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to parse result JSON:`n$($_.Exception.Message)",
            "NOAH Results",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "NOAH Reportability Results - $RecordLabel $($RecordIndex + 1) of $RecordCount"
    $form.Width = 1400
    $form.Height = 900
    $form.StartPosition = "CenterScreen"

    # Main split container: left (summary) | right (text with highlights)
    $splitMain = New-Object System.Windows.Forms.SplitContainer
    $splitMain.Dock = 'Fill'
    $splitMain.Orientation = 'Vertical'
    $splitMain.Panel1MinSize = 250
    $splitMain.Panel2MinSize = 300
    $splitMain.SplitterDistance = 400 
    
    $form.Add_Shown({
        if ($splitMain.Width -gt 400) {
            $splitMain.SplitterDistance = 400
        }
    })

    # === LEFT PANEL: Summary ===
    $rtbSummary = New-Object System.Windows.Forms.RichTextBox
    $rtbSummary.Dock = 'Fill'
    $rtbSummary.ReadOnly = $true
    $rtbSummary.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbSummary.WordWrap = $true

    # Build summary content
    $reportable = [bool]$resultJson.Reportable
    $reportableText = if ($reportable) { "REPORTABLE" } else { "NON-REPORTABLE" }
    $reportableColor = if ($reportable) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkRed }

    # Add summary header
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== CLASSIFICATION ===" -Bold $true
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text $reportableText -Bold $true -Color $reportableColor
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""

    # Flags
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== FLAGS ===" -Bold $true
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("ImpossibleCombination: {0}" -f $resultJson.ImpossibleCombination)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("MetastaticReport: {0}" -f $resultJson.MetastaticReport)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("PAYAC: {0}" -f $resultJson.PAYAC)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""

    # Diagnosis info
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== DIAGNOSIS ===" -Bold $true
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("DiagnosisDate: {0}" -f $resultJson.DiagnosisDate)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("MessageID: {0}" -f $resultJson.MessageID)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""

    # Coded Result
    if ($resultJson.CodedResult) {
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== CODED RESULT ===" -Bold $true
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("Histology: {0}" -f $resultJson.CodedResult.Histology) -Bold $true
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("Site: {0}" -f $resultJson.CodedResult.Site) -Bold $true
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("Behavior: {0}" -f $resultJson.CodedResult.Behavior) -Bold $true
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("Laterality: {0}" -f $resultJson.CodedResult.Laterality)
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("IsSkinCase: {0}" -f $resultJson.CodedResult.IsSkinCase)
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""
    }

    # Entity summary
    $entityCount = if ($resultJson.Entities) { $resultJson.Entities.Count } else { 0 }
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== ENTITIES ===" -Bold $true
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ("Total entities found: {0}" -f $entityCount)
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""

    # Color legend
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== COLOR LEGEND ===" -Bold $true
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "Cancer terms (Type 0)" -BackColor $script:EntityColors.Type0
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "Cytology terms (Type 1)" -BackColor $script:EntityColors.Type1
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "Site terms (Type 2)" -BackColor $script:EntityColors.Type2
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "Negated (any type)" -BackColor $script:EntityColors.Negated
    Add-ColoredTextToRichTextBox -Box $rtbSummary -Text ""

    # Entity details
    if ($resultJson.Entities -and $resultJson.Entities.Count -gt 0) {
        Add-ColoredTextToRichTextBox -Box $rtbSummary -Text "=== ENTITY DETAILS ===" -Bold $true
        foreach ($entity in $resultJson.Entities) {
            $negatedMarker = if ($entity.IsNegated) { " [NEGATED]" } else { "" }
            $typeLabel = switch ([int]$entity.EntityType) {
                0 { "Cancer" }
                1 { "Cytology" }
                2 { "Site" }
                default { "Type$($entity.EntityType)" }
            }
            $entityLine = "{0}: '{1}' (Code: {2}){3}" -f $typeLabel, $entity.EntityPhrase, $entity.Code, $negatedMarker
            
            # Color based on entity type
            $backColor = $null
            if ($entity.IsNegated) {
                $backColor = $script:EntityColors.Negated
            }
            else {
                switch ([int]$entity.EntityType) {
                    0 { $backColor = $script:EntityColors.Type0 }
                    1 { $backColor = $script:EntityColors.Type1 }
                    2 { $backColor = $script:EntityColors.Type2 }
                }
            }
            Add-ColoredTextToRichTextBox -Box $rtbSummary -Text $entityLine -BackColor $backColor
        }
    }

    $splitMain.Panel1.Controls.Add($rtbSummary)

    # === RIGHT PANEL: OBX Text with highlighting ===
    $rtbText = New-Object System.Windows.Forms.RichTextBox
    $rtbText.Dock = 'Fill'
    $rtbText.ReadOnly = $true
    $rtbText.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbText.WordWrap = $true
    $rtbText.ScrollBars = "Both"

    # Build the text content with entity highlighting
    Build-HighlightedOBXText -RichTextBox $rtbText -ResultJson $resultJson

    $splitMain.Panel2.Controls.Add($rtbText)

    # Bottom panel with buttons
    $pnlButtons = New-Object System.Windows.Forms.Panel
    $pnlButtons.Dock = 'Bottom'
    $pnlButtons.Height = 50

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = "Open Working Folder"
    $btnOpenFolder.Width = 150
    $btnOpenFolder.Location = New-Object System.Drawing.Point(10, 12)
    $btnOpenFolder.Add_Click({
        if (Test-Path -LiteralPath $WorkingFolder) {
            Start-Process "explorer.exe" -ArgumentList "`"$WorkingFolder`""
        }
    }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(170, 12)
    $btnClose.Add_Click({ $form.Close() })

    $pnlButtons.Controls.AddRange(@($btnOpenFolder, $btnClose))

    $form.Controls.Add($splitMain)
    $form.Controls.Add($pnlButtons)

    [void]$form.ShowDialog()
}

function Add-ColoredTextToRichTextBox {
    param(
        [System.Windows.Forms.RichTextBox]$Box,
        [string]$Text,
        [bool]$Bold = $false,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Empty,
        [System.Drawing.Color]$BackColor = [System.Drawing.Color]::Empty
    )

    $Box.SelectionStart = $Box.TextLength
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

    if ($Color -ne [System.Drawing.Color]::Empty) {
        $Box.SelectionColor = $Color
    }
    else {
        $Box.SelectionColor = $Box.ForeColor
    }

    if ($BackColor -ne [System.Drawing.Color]::Empty) {
        $Box.SelectionBackColor = $BackColor
    }
    else {
        $Box.SelectionBackColor = $Box.BackColor
    }

    $Box.AppendText($Text + "`r`n")
}

function Build-HighlightedOBXText {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [psobject]$ResultJson
    )

    $obxTexts = $ResultJson.OBXTexts
    $entities = $ResultJson.Entities

    if (-not $obxTexts) {
        $RichTextBox.Text = "(No OBXTexts in result)"
        return
    }

    # Build entities lookup by OBX segment
    $entitiesBySegment = @{}
    if ($entities) {
        foreach ($entity in $entities) {
            $segNum = [int]$entity.OBXSegment
            if (-not $entitiesBySegment.ContainsKey($segNum)) {
                $entitiesBySegment[$segNum] = @()
            }
            $entitiesBySegment[$segNum] += $entity
        }
    }

    # Calculate cumulative lengths of each segment in the combined text
    # NOAH calculates offsets relative to the entire combined OBXText (all fields concatenated)
    # We need to adjust offsets by subtracting the cumulative length of previous segments
    # Build the combined text exactly as NOAH would (concatenating all segments with \r\n separators)
    $segmentOrder = @(0, 1, 2, 3, 4, 5, 6, 7, 8)
    $cumulativeLengths = @{}
    $cumulativeLength = 0
    
    foreach ($segNum in $segmentOrder) {
        $fieldName = $script:OBXSegmentMap[$segNum]
        
        # Store cumulative length BEFORE this segment
        $cumulativeLengths[$segNum] = $cumulativeLength
        
        if (-not $fieldName) { 
            continue 
        }

        $textValue = $obxTexts.$fieldName
        if ([string]::IsNullOrWhiteSpace($textValue)) {
            continue
        }

        # Normalize line endings to match what NOAH used for offset calculation
        # NOAH likely uses \r\n (CRLF) for offsets, so normalize to that
        $normalizedText = $textValue -replace "`r`n", "`r`n" -replace "`r", "`r`n" -replace "`n", "`r`n"
        
        # Add this segment's length to cumulative
        # If this is not the first segment, add 2 for the \r\n separator
        if ($cumulativeLength -gt 0) {
            $cumulativeLength += 2  # \r\n separator
        }
        $cumulativeLength += $normalizedText.Length
    }
    
    # Process each OBX text field in order
    foreach ($segNum in $segmentOrder) {
        $fieldName = $script:OBXSegmentMap[$segNum]
        if (-not $fieldName) { continue }

        $textValue = $obxTexts.$fieldName
        if ([string]::IsNullOrWhiteSpace($textValue)) { continue }

        # Normalize line endings to match what NOAH used for offset calculation
        # NOAH likely uses \r\n (CRLF) for offsets, so normalize to that
        $textValue = $textValue -replace "`r`n", "`r`n" -replace "`r", "`r`n" -replace "`n", "`r`n"

        # Add section header
        Add-ColoredTextToRichTextBox -Box $RichTextBox -Text "=== $fieldName (Segment $segNum) ===" -Bold $true
        
        # Get entities for this segment, sorted by offset
        $segmentEntities = @()
        if ($entitiesBySegment.ContainsKey($segNum)) {
            $segmentEntities = $entitiesBySegment[$segNum] | Sort-Object -Property Offset
        }

        # Insert text with highlighting
        if ($segmentEntities.Count -eq 0) {
            # No entities - just add plain text
            $RichTextBox.SelectionStart = $RichTextBox.TextLength
            $RichTextBox.SelectionLength = 0
            $RichTextBox.SelectionFont = $RichTextBox.Font
            $RichTextBox.SelectionColor = $RichTextBox.ForeColor
            $RichTextBox.SelectionBackColor = $RichTextBox.BackColor
            $RichTextBox.AppendText($textValue + "`r`n")
        }
        else {
            # Build text with entity highlighting
            # Record position BEFORE adding text (after header and its newline)
            $startPos = $RichTextBox.TextLength
            
            # First, add the entire text as plain (without trailing newline yet)
            $RichTextBox.SelectionStart = $RichTextBox.TextLength
            $RichTextBox.SelectionLength = 0
            $RichTextBox.SelectionFont = $RichTextBox.Font
            $RichTextBox.SelectionColor = $RichTextBox.ForeColor
            $RichTextBox.SelectionBackColor = $RichTextBox.BackColor
            $RichTextBox.AppendText($textValue)

            # Get the cumulative length of all previous segments
            # This is the offset adjustment needed since NOAH calculates offsets relative to combined text
            $offsetAdjustment = $cumulativeLengths[$segNum]

            # Now apply highlighting to each entity (before adding the final newline)
            foreach ($entity in $segmentEntities) {
                $offset = [int]$entity.Offset
                $length = [int]$entity.Length
                $entityPhrase = [string]$entity.EntityPhrase

                # Adjust offset: NOAH calculates offsets relative to the entire combined OBXText
                # We need to subtract the cumulative length of all previous segments
                $adjustedOffset = $offset - $offsetAdjustment

                # Verify the adjusted offset by checking if the entity phrase matches at that position
                # If not, try to find it in the text (offset might be wrong due to encoding/line ending differences)
                $actualOffset = $adjustedOffset
                if ($adjustedOffset -ge 0 -and $adjustedOffset + $length -le $textValue.Length) {
                    $textAtOffset = $textValue.Substring($adjustedOffset, [Math]::Min($length, $textValue.Length - $adjustedOffset))
                    if ($textAtOffset -ne $entityPhrase -and -not [string]::IsNullOrWhiteSpace($entityPhrase)) {
                        # Try to find the phrase in the text (case-insensitive search)
                        $foundIndex = $textValue.IndexOf($entityPhrase, [StringComparison]::OrdinalIgnoreCase)
                        if ($foundIndex -ge 0) {
                            $actualOffset = $foundIndex
                        }
                    }
                }
                elseif ($adjustedOffset -lt 0) {
                    # Offset is negative after adjustment - this shouldn't happen, but try to find the phrase anyway
                    if (-not [string]::IsNullOrWhiteSpace($entityPhrase)) {
                        $foundIndex = $textValue.IndexOf($entityPhrase, [StringComparison]::OrdinalIgnoreCase)
                        if ($foundIndex -ge 0) {
                            $actualOffset = $foundIndex
                        }
                        else {
                            # Skip this entity if we can't find it
                            continue
                        }
                    }
                    else {
                        continue
                    }
                }
                else {
                    # Offset is beyond the text length - try to find the phrase
                    if (-not [string]::IsNullOrWhiteSpace($entityPhrase)) {
                        $foundIndex = $textValue.IndexOf($entityPhrase, [StringComparison]::OrdinalIgnoreCase)
                        if ($foundIndex -ge 0) {
                            $actualOffset = $foundIndex
                        }
                        else {
                            # Skip this entity if we can't find it
                            continue
                        }
                    }
                    else {
                        continue
                    }
                }

                # Calculate position in RichTextBox
                # Offset is 0-based relative to the start of textValue
                $highlightStart = $startPos + $actualOffset
                $highlightLength = $length

                # Ensure we don't exceed bounds
                if ($highlightStart -lt $startPos) { continue }
                if ($highlightStart + $highlightLength -gt $RichTextBox.TextLength) {
                    $highlightLength = $RichTextBox.TextLength - $highlightStart
                }
                if ($highlightLength -le 0) { continue }

                # Determine color based on entity type and negation
                $backColor = $script:EntityColors.Type0  # default to cancer
                if ($entity.IsNegated) {
                    $backColor = $script:EntityColors.Negated
                }
                else {
                    switch ([int]$entity.EntityType) {
                        0 { $backColor = $script:EntityColors.Type0 }
                        1 { $backColor = $script:EntityColors.Type1 }
                        2 { $backColor = $script:EntityColors.Type2 }
                    }
                }

                # Apply highlighting
                $RichTextBox.SelectionStart = $highlightStart
                $RichTextBox.SelectionLength = $highlightLength
                $RichTextBox.SelectionBackColor = $backColor
            }
            
            # Add the trailing newline after all highlighting is applied
            $RichTextBox.AppendText("`r`n")
        }

        Add-ColoredTextToRichTextBox -Box $RichTextBox -Text ""
    }

    # Reset selection to start
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0
}

