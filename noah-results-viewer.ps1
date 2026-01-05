# noah-results-viewer.ps1
# Display NOAH reportability results with color-coded entity highlighting

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Map OBXSegment numbers to OBXTexts keys
$script:OBXSegmentMap = @{
    0 = "FinalDiagnosis"
    1 = "TextDiagnosis"
    2 = "ClinicalHistory"
    3 = "NatureOfSpecimen"
    4 = "GrossPathology"
    5 = "MicroPathology"
    6 = "Comment"
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
    $splitMain.SplitterDistance = 350
    $splitMain.Panel1MinSize = 250

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

    # Process each OBX text field in order
    $segmentOrder = @(0, 1, 2, 3, 4, 5, 6, 7, 8)
    
    foreach ($segNum in $segmentOrder) {
        $fieldName = $script:OBXSegmentMap[$segNum]
        if (-not $fieldName) { continue }

        $textValue = $obxTexts.$fieldName
        if ([string]::IsNullOrWhiteSpace($textValue)) { continue }

        # Add section header
        Add-ColoredTextToRichTextBox -Box $RichTextBox -Text "=== $fieldName (Segment $segNum) ===" -Bold $true
        
        # Get entities for this segment, sorted by offset descending (to apply from end to start)
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
            $startPos = $RichTextBox.TextLength
            
            # First, add the entire text as plain
            $RichTextBox.SelectionStart = $RichTextBox.TextLength
            $RichTextBox.SelectionLength = 0
            $RichTextBox.SelectionFont = $RichTextBox.Font
            $RichTextBox.SelectionColor = $RichTextBox.ForeColor
            $RichTextBox.SelectionBackColor = $RichTextBox.BackColor
            $RichTextBox.AppendText($textValue + "`r`n")

            # Now apply highlighting to each entity
            foreach ($entity in $segmentEntities) {
                $offset = [int]$entity.Offset
                $length = [int]$entity.Length

                # Calculate position in RichTextBox
                $highlightStart = $startPos + $offset
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
        }

        Add-ColoredTextToRichTextBox -Box $RichTextBox -Text ""
    }

    # Reset selection to start
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0
}

