# test-site-laterality-ui.ps1
# UI dialogs for site/laterality testing

function Show-TestSiteLateralityDialog {
    <#
    .SYNOPSIS
    Show input dialog for testing site/laterality heuristics

    .OUTPUTS
    The text entered by the user, or $null if cancelled
    #>

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Test Site/Laterality Heuristics"
    $dialog.Width = 600
    $dialog.Height = 400
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(400, 300)

    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
    $lblPrompt.Size = New-Object System.Drawing.Size(560, 20)
    $lblPrompt.Text = "Enter pathology text to test:"
    $lblPrompt.Anchor = "Top,Left,Right"

    $txtInput = New-Object System.Windows.Forms.TextBox
    $txtInput.Location = New-Object System.Drawing.Point(10, 35)
    $txtInput.Size = New-Object System.Drawing.Size(560, 270)
    $txtInput.Multiline = $true
    $txtInput.ScrollBars = "Both"
    $txtInput.WordWrap = $true
    $txtInput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtInput.Anchor = "Top,Left,Right,Bottom"

    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = "Test Heuristics"
    $btnTest.Width = 120
    $btnTest.Location = New-Object System.Drawing.Point(340, 320)
    $btnTest.Anchor = "Bottom,Right"
    $btnTest.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(470, 320)
    $btnCancel.Anchor = "Bottom,Right"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dialog.Controls.AddRange(@($lblPrompt, $txtInput, $btnTest, $btnCancel))
    $dialog.AcceptButton = $btnTest
    $dialog.CancelButton = $btnCancel

    $dialogResult = $dialog.ShowDialog()

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $text = $txtInput.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    return $null
}

function Show-TestSiteLateralityResults {
    <#
    .SYNOPSIS
    Show results window for site/laterality heuristics test with source text highlighting

    .PARAMETER Result
    The result hashtable from Test-SiteLateralityHeuristics

    .PARAMETER SourceText
    Optional source text to display with highlighting (used for XML)

    .PARAMETER ObxSegments
    Optional array of raw OBX segment strings (used for HL7)

    .PARAMETER SkipCodes
    Optional array of OBX-3.1 codes that are skipped
    #>
    param(
        [Parameter(Mandatory=$true)][hashtable]$Result,
        [string]$SourceText = "",
        [array]$ObxSegments = @(),
        [array]$SkipCodes = @()
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $hasObxSegments = ($ObxSegments -and $ObxSegments.Count -gt 0)
    $hasSourceText = $hasObxSegments -or (-not [string]::IsNullOrWhiteSpace($SourceText))

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Site/Laterality Test Results"
    $dialog.Width = 800
    $dialog.Height = if ($hasSourceText) { 900 } else { 350 }
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(900, 350)

    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = 'Fill'
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(10)

    if ($hasSourceText) {
        $splitContainer = New-Object System.Windows.Forms.SplitContainer
        $splitContainer.Dock = 'Fill'
        $splitContainer.Orientation = 'Horizontal'
        $splitContainer.Panel1MinSize = 100
        $splitContainer.Panel2MinSize = 100

        $rtbResults = New-Object System.Windows.Forms.RichTextBox
        $rtbResults.Dock = 'Fill'
        $rtbResults.ReadOnly = $true
        $rtbResults.Font = New-Object System.Drawing.Font("Consolas", 10)
        $rtbResults.BackColor = [System.Drawing.Color]::White

        $lblSourceText = New-Object System.Windows.Forms.Label
        $lblSourceText.Text = if ($hasObxSegments) { "OBX SEGMENTS (skipped in gray, matched phrases highlighted)" } else { "SOURCE TEXT (matched phrases highlighted)" }
        $lblSourceText.Dock = 'Top'
        $lblSourceText.Height = 20
        $lblSourceText.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

        $rtbSourceText = New-Object System.Windows.Forms.RichTextBox
        $rtbSourceText.Dock = 'Fill'
        $rtbSourceText.ReadOnly = $true
        $rtbSourceText.Font = New-Object System.Drawing.Font("Consolas", 9)
        $rtbSourceText.BackColor = [System.Drawing.Color]::White
        $rtbSourceText.WordWrap = $true

        $splitContainer.Panel1.Controls.Add($rtbResults)
        $splitContainer.Panel2.Controls.Add($rtbSourceText)
        $splitContainer.Panel2.Controls.Add($lblSourceText)

        $mainPanel.Controls.Add($splitContainer)
    }
    else {
        $rtbResults = New-Object System.Windows.Forms.RichTextBox
        $rtbResults.Dock = 'Fill'
        $rtbResults.ReadOnly = $true
        $rtbResults.Font = New-Object System.Drawing.Font("Consolas", 10)
        $rtbResults.BackColor = [System.Drawing.Color]::White

        $mainPanel.Controls.Add($rtbResults)
    }

    # Build results text
    # Show source info if available (from current record test)
    if ($Result.SourceInfo) {
        $rtbResults.SelectionFont = Get-BoldFont $rtbResults.Font
        $rtbResults.AppendText("SOURCE`r`n")
        $rtbResults.SelectionFont = $rtbResults.Font
        $rtbResults.AppendText("  Record:       $($Result.SourceInfo)`r`n")
        # if ($Result.TextLength) {
        #     $rtbResults.AppendText("  Text length:  $($Result.TextLength) characters`r`n")
        # }
        $rtbResults.AppendText("`r`n")
    }

    $rtbResults.SelectionFont = Get-BoldFont $rtbResults.Font
    $rtbResults.AppendText("PRIMARY SITE`r`n")
    $rtbResults.SelectionFont = $rtbResults.Font

    if ($Result.SiteCode) {
        $rtbResults.AppendText("  Code:         $($Result.SiteCode)`r`n")

        $matchTypeDesc = switch ($Result.MatchType) {
            "site-coding-rule" { "Site coding rule" }
            "melanoma-dict" { "Melanoma dictionary" }
            "standard-dict" { "Standard dictionary" }
            default { $Result.MatchType }
        }
        $rtbResults.AppendText("  Match Type:   $matchTypeDesc`r`n")

        if ($Result.PatternPriority) {
            $rtbResults.AppendText("  Priority:     $($Result.PatternPriority)`r`n")
        }

        $rtbResults.AppendText("  Matched:      `"$($Result.MatchedPhrase)`"`r`n")
    }
    else {
        $rtbResults.AppendText("  (No match found)`r`n")
    }

    $rtbResults.AppendText("`r`n")
    $rtbResults.SelectionFont = Get-BoldFont $rtbResults.Font
    $rtbResults.AppendText("LATERALITY`r`n")
    $rtbResults.SelectionFont = $rtbResults.Font

    if ($Result.LateralityCode) {
        $rtbResults.AppendText("  Code:         $($Result.LateralityCode)`r`n")
        $rtbResults.AppendText("  Description:  $($Result.LateralityDescription)`r`n")
        $requiresLat = if ($Result.SiteRequiresLaterality) { "Yes" } else { "No" }
        $rtbResults.AppendText("  Site requires laterality: $requiresLat`r`n")
    }
    else {
        $rtbResults.AppendText("  (No site to determine laterality)`r`n")
    }

    # Populate source text with highlighting
    if ($hasSourceText) {
        if ($hasObxSegments) {
            # HL7 mode: Show each OBX segment with its identifier
            # Gray out segments that match skip codes
            $skipCodesUpper = @($SkipCodes | ForEach-Object { $_.ToUpper() })
            $firstMatchPos = -1

            foreach ($obx in $ObxSegments) {
                $fields = $obx -split '\|'
                $obx3 = if ($fields.Count -gt 3) { $fields[3] } else { "" }
                $obx5 = if ($fields.Count -gt 5) { $fields[5] } else { "" }

                # Get OBX-3.1 (first component before ^)
                $obx3Components = $obx3 -split '\^'
                $obx3Code = $obx3Components[0].Trim().ToUpper()

                # Check if this segment should be skipped
                $isSkipped = $skipCodesUpper -contains $obx3Code

                # Build the identifier line (truncate if too long)
                $identifierLine = "OBX|$($fields[1])|$($fields[2])|$obx3"
                if ($identifierLine.Length -gt 80) {
                    $identifierLine = $identifierLine.Substring(0, 77) + "..."
                }

                # Process OBX-5 text (handle HL7 escape sequences)
                $textContent = $obx5
                $textContent = $textContent -replace '\\X0D\\', "`r"
                $textContent = $textContent -replace '\\X0A\\', "`n"
                $textContent = $textContent -replace '\\E\\', '\'
                $textContent = $textContent -replace '\\F\\', '|'
                $textContent = $textContent -replace '\\S\\', '^'
                $textContent = $textContent -replace '\\T\\', '&'
                $textContent = $textContent -replace '\\R\\', '~'

                # Normalize line endings
                $textContent = $textContent -replace "`r`n", "`n"
                $textContent = $textContent -replace "`r", "`n"

                if ($isSkipped) {
                    # Gray text for skipped segments
                    $rtbSourceText.SelectionColor = [System.Drawing.Color]::Gray
                    $rtbSourceText.AppendText("$identifierLine [SKIPPED]`n")
                    if (-not [string]::IsNullOrWhiteSpace($textContent)) {
                        $rtbSourceText.AppendText("$textContent`n")
                    }
                    $rtbSourceText.AppendText("`n")
                    $rtbSourceText.SelectionColor = [System.Drawing.Color]::Black
                }
                else {
                    $rtbSourceText.SelectionFont = Get-BoldFont $rtbSourceText.Font
                    $rtbSourceText.SelectionColor = [System.Drawing.Color]::DarkBlue
                    $rtbSourceText.AppendText("$identifierLine`n")
                    $rtbSourceText.SelectionFont = $rtbSourceText.Font
                    $rtbSourceText.SelectionColor = [System.Drawing.Color]::Black

                    if (-not [string]::IsNullOrWhiteSpace($textContent)) {
                        # Track where actual text content starts for finding first match
                        $textStartPos = $rtbSourceText.TextLength
                        $rtbSourceText.AppendText("$textContent`n")

                        # Check if this segment contains the first match
                        if ($firstMatchPos -lt 0 -and $Result.MatchedPhrase) {
                            $matchIdx = $textContent.ToLower().IndexOf($Result.MatchedPhrase.ToLower())
                            if ($matchIdx -ge 0) {
                                $firstMatchPos = $textStartPos + $matchIdx
                            }
                        }
                    }
                    $rtbSourceText.AppendText("`n")
                }
            }

            # Now apply highlighting to non-skipped content
            # Highlight the matched site phrase (green background)
            if ($Result.MatchedPhrase -and $Result.MatchedPhrase -ne "melanoma (fallback)" -and $Result.MatchedPhrase -ne "biomarker combination (EGFR/PD-L1/ALK)") {
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText $Result.MatchedPhrase -BackColor ([System.Drawing.Color]::LightGreen) -ForeColor ([System.Drawing.Color]::Black)
            }

            # Highlight laterality keywords (blue for both left and right)
            if ($Result.SiteRequiresLaterality) {
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText "left" -BackColor ([System.Drawing.Color]::LightSkyBlue) -ForeColor ([System.Drawing.Color]::Black) -WholeWord $true
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText "right" -BackColor ([System.Drawing.Color]::LightSkyBlue) -ForeColor ([System.Drawing.Color]::Black) -WholeWord $true
            }

            # Scroll to first match if found
            # if ($firstMatchPos -ge 0) {
            #     $rtbSourceText.SelectionStart = $firstMatchPos
            #     $rtbSourceText.ScrollToCaret()
            #     $rtbSourceText.SelectionLength = 0
            # }
        }
        else {
            # XML: Simple text display
            # Normalize line endings to match what RichTextBox uses internally
            $normalizedText = $SourceText -replace "`r`n", "`n"
            $normalizedText = $normalizedText -replace "`r", "`n"
            $rtbSourceText.Text = $normalizedText

            # Bold the XML item headers
            # Todo: may need to re-evaluate this at some point--missing remarks, etc.
            $xmlHeaders = @("textDxProcPath:", "textDxProcPe:", "textDxProcLabTests:")
            foreach ($header in $xmlHeaders) {
                Add-RichTextBoxBold -RichTextBox $rtbSourceText -SearchText $header
            }

            if ($Result.MatchedPhrase -and $Result.MatchedPhrase -ne "melanoma (fallback)" -and $Result.MatchedPhrase -ne "biomarker combination (EGFR/PD-L1/ALK)") {
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText $Result.MatchedPhrase -BackColor ([System.Drawing.Color]::LightGreen) -ForeColor ([System.Drawing.Color]::Black)
            }

            if ($Result.SiteRequiresLaterality) {
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText "left" -BackColor ([System.Drawing.Color]::LightSkyBlue) -ForeColor ([System.Drawing.Color]::Black) -WholeWord $true
                Add-RichTextBoxHighlight -RichTextBox $rtbSourceText -SearchText "right" -BackColor ([System.Drawing.Color]::LightSkyBlue) -ForeColor ([System.Drawing.Color]::Black) -WholeWord $true
            }

            # Scroll to first match if found
            # if ($Result.MatchedPhrase -and $Result.MatchedPhrase -ne "melanoma (fallback)" -and $Result.MatchedPhrase -ne "biomarker combination (EGFR/PD-L1/ALK)") {
            #     $matchIndex = $normalizedText.ToLower().IndexOf($Result.MatchedPhrase.ToLower())
            #     if ($matchIndex -ge 0) {
            #         $rtbSourceText.SelectionStart = $matchIndex
            #         $rtbSourceText.ScrollToCaret()
            #         $rtbSourceText.SelectionLength = 0
            #     }
            # }
        }
    }

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = 'Bottom'
    $bottomPanel.Height = 45

    $lblLegendLabel = New-Object System.Windows.Forms.Label
    $lblLegendLabel.Text = "Legend:"
    $lblLegendLabel.Location = New-Object System.Drawing.Point(10, 14)
    $lblLegendLabel.AutoSize = $true
    $lblLegendLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $pnlSiteColor = New-Object System.Windows.Forms.Panel
    $pnlSiteColor.Location = New-Object System.Drawing.Point(70, 14)
    $pnlSiteColor.Size = New-Object System.Drawing.Size(14, 14)
    $pnlSiteColor.BackColor = [System.Drawing.Color]::LightGreen
    $pnlSiteColor.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblSiteText = New-Object System.Windows.Forms.Label
    $lblSiteText.Text = "Site"
    $lblSiteText.Location = New-Object System.Drawing.Point(88, 14)
    $lblSiteText.AutoSize = $true
    $lblSiteText.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $pnlLatColor = New-Object System.Windows.Forms.Panel
    $pnlLatColor.Location = New-Object System.Drawing.Point(125, 14)
    $pnlLatColor.Size = New-Object System.Drawing.Size(14, 14)
    $pnlLatColor.BackColor = [System.Drawing.Color]::LightSkyBlue
    $pnlLatColor.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblLatText = New-Object System.Windows.Forms.Label
    $lblLatText.Text = "Laterality"
    $lblLatText.Location = New-Object System.Drawing.Point(143, 14)
    $lblLatText.AutoSize = $true
    $lblLatText.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Skipped legend (only for HL7 with OBX segments)
    $pnlSkippedColor = New-Object System.Windows.Forms.Panel
    $pnlSkippedColor.Location = New-Object System.Drawing.Point(210, 14)
    $pnlSkippedColor.Size = New-Object System.Drawing.Size(14, 14)
    $pnlSkippedColor.BackColor = [System.Drawing.Color]::Gray
    $pnlSkippedColor.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblSkippedText = New-Object System.Windows.Forms.Label
    $lblSkippedText.Text = "Skipped"
    $lblSkippedText.Location = New-Object System.Drawing.Point(228, 14)
    $lblSkippedText.AutoSize = $true
    $lblSkippedText.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Width = 100
    $btnOk.Location = New-Object System.Drawing.Point(570, 8)
    $btnOk.Anchor = 'Right,Bottom'
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = "Copy Results"
    $btnCopy.Width = 100
    $btnCopy.Location = New-Object System.Drawing.Point(678, 8)
    $btnCopy.Anchor = 'Right,Bottom'
    $btnCopy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($rtbResults.Text)
    })

    if ($hasSourceText) {
        if ($hasObxSegments) {
            # HL7 - show all legend items including Skipped
            $bottomPanel.Controls.AddRange(@($lblLegendLabel, $pnlSiteColor, $lblSiteText, $pnlLatColor, $lblLatText, $pnlSkippedColor, $lblSkippedText, $btnOk, $btnCopy))
        }
        else {
            # XML - no Skipped legend
            $bottomPanel.Controls.AddRange(@($lblLegendLabel, $pnlSiteColor, $lblSiteText, $pnlLatColor, $lblLatText, $btnOk, $btnCopy))
        }
    }
    else {
        $bottomPanel.Controls.AddRange(@($btnOk, $btnCopy))
    }

    $dialog.Controls.Add($mainPanel)
    $dialog.Controls.Add($bottomPanel)
    $dialog.AcceptButton = $btnOk

    # Set splitter distance after form is shown (to avoid size constraint errors during init)
    if ($hasSourceText) {
        $dialog.Add_Shown({
            param($formSender, $formEventArgs)
            # Set top panel to ~1/3 of available height (bottom panel gets ~2/3)
            $splitContainer.SplitterDistance = [int]($splitContainer.Height / 3)
        }.GetNewClosure())
    }

    [void]$dialog.ShowDialog()
}

function Add-RichTextBoxHighlight {
    <#
    .SYNOPSIS
    Highlight all occurrences of a search string in a RichTextBox

    .PARAMETER RichTextBox
    The RichTextBox control to search in

    .PARAMETER SearchText
    The text to search for and highlight

    .PARAMETER BackColor
    The background color for highlighting

    .PARAMETER ForeColor
    The foreground (text) color for highlighting

    .PARAMETER WholeWord
    If true, only match whole words
    #>
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$SearchText,
        [System.Drawing.Color]$BackColor,
        [System.Drawing.Color]$ForeColor,
        [bool]$WholeWord = $false
    )

    if ([string]::IsNullOrEmpty($SearchText)) { return }

    $text = $RichTextBox.Text
    $searchLower = $SearchText.ToLower()
    $textLower = $text.ToLower()

    $startIndex = 0
    while ($true) {
        $foundIndex = $textLower.IndexOf($searchLower, $startIndex)
        if ($foundIndex -lt 0) { break }

        # Check whole word boundaries if required
        $isWholeWord = $true
        if ($WholeWord) {
            # Check character before
            if ($foundIndex -gt 0) {
                $charBefore = $text[$foundIndex - 1]
                if ([char]::IsLetterOrDigit($charBefore)) {
                    $isWholeWord = $false
                }
            }
            # Check character after
            $endPos = $foundIndex + $SearchText.Length
            if ($endPos -lt $text.Length) {
                $charAfter = $text[$endPos]
                if ([char]::IsLetterOrDigit($charAfter)) {
                    $isWholeWord = $false
                }
            }
        }

        if ($isWholeWord) {
            $RichTextBox.SelectionStart = $foundIndex
            $RichTextBox.SelectionLength = $SearchText.Length
            $RichTextBox.SelectionBackColor = $BackColor
            $RichTextBox.SelectionColor = $ForeColor
        }

        $startIndex = $foundIndex + 1
    }

    # Reset selection
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0
}

function Add-RichTextBoxBold {
    <#
    .SYNOPSIS
    Bold all occurrences of a search string in a RichTextBox

    .PARAMETER RichTextBox
    The RichTextBox control to search in

    .PARAMETER SearchText
    The text to search for and bold
    #>
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$SearchText
    )

    if ([string]::IsNullOrEmpty($SearchText)) { return }

    $text = $RichTextBox.Text
    $searchLower = $SearchText.ToLower()
    $textLower = $text.ToLower()
    $boldFont = Get-BoldFont $RichTextBox.Font

    $startIndex = 0
    while ($true) {
        $foundIndex = $textLower.IndexOf($searchLower, $startIndex)
        if ($foundIndex -lt 0) { break }

        $RichTextBox.SelectionStart = $foundIndex
        $RichTextBox.SelectionLength = $SearchText.Length
        $RichTextBox.SelectionFont = $boldFont

        $startIndex = $foundIndex + 1
    }

    # Reset selection
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0
}
