# test-site-laterality.ps1
# Test site/laterality heuristics on custom text

. "$PSScriptRoot\assign-site-laterality.ps1"

function Test-SiteLateralityHeuristics {
    <#
    .SYNOPSIS
    Run site/laterality heuristics on input text and return detailed result

    .PARAMETER Text
    The pathology text to analyze

    .OUTPUTS
    Hashtable with site code, description, match type, laterality, etc.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Text
    )

    $scriptDir = $PSScriptRoot

    # Load maps (with caching)
    $maps = Get-CachedMaps -ScriptDir $scriptDir
    $topoMap = $maps.TopoMap
    $melTopoMap = $maps.MelTopoMap
    $lateralityCodes = $maps.LateralityCodes

    $low = $Text.ToLower()

    $result = @{
        SiteCode = ""
        SiteDescription = ""
        MatchType = "none"
        MatchedPhrase = ""
        LateralityCode = ""
        LateralityDescription = ""
        SiteRequiresLaterality = $false
    }

    # Site Assignment Tiers:
    # 1. Hard-coded patterns
    if ($low -match '\b(invasive ductal carcinoma|metastatic mammary carcinoma|progesterone receptor|estrogen receptor|ductal carcinoma in-situ)\b') {
        $result.SiteCode = "C509"
        $result.SiteDescription = "Breast, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\brenal cell carcinoma\b') {
        $result.SiteCode = "C649"
        $result.SiteDescription = "Kidney, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\b(prostatectomy|prostatic adenocarcinoma|gleason)\b') {
        $result.SiteCode = "C619"
        $result.SiteDescription = "Prostate gland"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\b(cll|plasma cell myeloma|small lymphocytic lymphoma|chronic lymphocytic leukemia)\b') {
        $result.SiteCode = "C421"
        $result.SiteDescription = "Bone marrow"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\b(follicular lymphoma|diffuse large b-cell lymphoma|dlbcl)\b') {
        $result.SiteCode = "C779"
        $result.SiteDescription = "Lymph node, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\b(mlh1|pms2|msh2|msh6)\b') {
        $result.SiteCode = "C189"
        $result.SiteDescription = "Colon, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = $Matches[0]
    }
    elseif ($low -match '\bbone marrow\b') {
        $result.SiteCode = "C421"
        $result.SiteDescription = "Bone marrow"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = "bone marrow"
    }
    elseif ($low -match '\bserous carcinoma\b') {
        $result.SiteCode = "C579"
        $result.SiteDescription = "Female genital tract, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = "serous carcinoma"
    }
    elseif (
        $low -like '*dako pd-l1 22c3*' -or
        $low -like '*non-small cell carcinoma*' -or
        $low -match '\bnsclc\b' -or
        ($low -match '\begfr\b' -and $low -match 'pd-l1') -or
        ($low -match '\begfr\b' -and $low -match '\balk\b') -or
        ($low -match 'pd-l1' -and $low -match '\balk\b')
    ) {
        $result.SiteCode = "C349"
        $result.SiteDescription = "Lung, NOS"
        $result.MatchType = "hard-coded"
        if ($low -like '*dako pd-l1 22c3*') { $result.MatchedPhrase = "dako pd-l1 22c3" }
        elseif ($low -like '*non-small cell carcinoma*') { $result.MatchedPhrase = "non-small cell carcinoma" }
        elseif ($low -match '\bnsclc\b') { $result.MatchedPhrase = "nsclc" }
        else { $result.MatchedPhrase = "biomarker combination (EGFR/PD-L1/ALK)" }
    }
    elseif ($low -match '\bbraf mutation analysis\b') {
        $result.SiteCode = "C449"
        $result.SiteDescription = "Skin, NOS"
        $result.MatchType = "hard-coded"
        $result.MatchedPhrase = "braf mutation analysis"
    }
    else {
        # 2. Melanoma dictionary - if "melanoma" found
        $hasMel = $low.Contains("melanoma")

        if ($hasMel) {
            # Find best match in melanoma topography dictionary
            $bestCode = ""
            $bestPos = 0
            $bestPhrase = ""

            foreach ($row in $melTopoMap) {
                $code = $row.Code
                $phrase = $row.SearchPhrase
                $pos = $low.IndexOf($phrase)
                if ($pos -ge 0) {
                    $p = $pos + 1
                    if ($bestPos -eq 0 -or $p -lt $bestPos) {
                        $bestPos = $p
                        $bestCode = $code
                        $bestPhrase = $phrase
                    }
                }
            }

            if ($bestCode) {
                $result.SiteCode = $bestCode
                $result.MatchType = "melanoma-dict"
                $result.MatchedPhrase = $bestPhrase
            }
            else {
                # Fallback for melanoma with no specific site
                $result.SiteCode = "C449"
                $result.SiteDescription = "Skin, NOS"
                $result.MatchType = "melanoma-dict"
                $result.MatchedPhrase = "melanoma (fallback)"
            }
        }
        else {
            # 3. Standard dictionary - earliest match wins
            $bestCode = ""
            $bestPos = 0
            $bestPhrase = ""

            foreach ($row in $topoMap) {
                $code = $row.Code
                $phrase = $row.SearchPhrase
                $pos = $low.IndexOf($phrase)
                if ($pos -ge 0) {
                    $p = $pos + 1
                    if ($bestPos -eq 0 -or $p -lt $bestPos) {
                        $bestPos = $p
                        $bestCode = $code
                        $bestPhrase = $phrase
                    }
                }
            }

            if ($bestCode) {
                $result.SiteCode = $bestCode
                $result.MatchType = "standard-dict"
                $result.MatchedPhrase = $bestPhrase
            }
        }
    }

    # Look up site description if we have a code but no description yet
    if ($result.SiteCode -and -not $result.SiteDescription) {
        # Try to find description in dictionaries
        $foundDesc = $false
        foreach ($row in $topoMap) {
            if ($row.Code -eq $result.SiteCode) {
                # Use first phrase as a rough description
                $result.SiteDescription = "Site $($result.SiteCode)"
                $foundDesc = $true
                break
            }
        }
        if (-not $foundDesc) {
            $result.SiteDescription = "Site $($result.SiteCode)"
        }
    }

    # Laterality Assignment
    if ($result.SiteCode) {
        $result.SiteRequiresLaterality = $lateralityCodes.ContainsKey($result.SiteCode)

        if ($result.SiteRequiresLaterality) {
            # Search for left/right with word boundaries
            $leftMatch = [regex]::Match($low, '\bleft\b')
            $rightMatch = [regex]::Match($low, '\bright\b')

            $pLeft = if ($leftMatch.Success) { $leftMatch.Index } else { -1 }
            $pRight = if ($rightMatch.Success) { $rightMatch.Index } else { -1 }

            if ($pLeft -ge 0 -and ($pRight -lt 0 -or $pLeft -lt $pRight)) {
                $result.LateralityCode = "2"
                $result.LateralityDescription = "Left"
            }
            elseif ($pRight -ge 0) {
                $result.LateralityCode = "1"
                $result.LateralityDescription = "Right"
            }
            else {
                # Site requires laterality but none found
                $result.LateralityCode = "9"
                $result.LateralityDescription = "Unknown"
            }
        }
        else {
            # Site doesn't require laterality
            $result.LateralityCode = "0"
            $result.LateralityDescription = "Not Applicable"
        }
    }

    return $result
}

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

    # Label
    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
    $lblPrompt.Size = New-Object System.Drawing.Size(560, 20)
    $lblPrompt.Text = "Enter pathology text to test:"
    $lblPrompt.Anchor = "Top,Left,Right"

    # Text box
    $txtInput = New-Object System.Windows.Forms.TextBox
    $txtInput.Location = New-Object System.Drawing.Point(10, 35)
    $txtInput.Size = New-Object System.Drawing.Size(560, 270)
    $txtInput.Multiline = $true
    $txtInput.ScrollBars = "Both"
    $txtInput.WordWrap = $true
    $txtInput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtInput.Anchor = "Top,Left,Right,Bottom"

    # Buttons
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
    Show results window for site/laterality heuristics test

    .PARAMETER Result
    The result hashtable from Test-SiteLateralityHeuristics
    #>
    param(
        [Parameter(Mandatory=$true)][hashtable]$Result
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Site/Laterality Test Results"
    $dialog.Width = 510
    $dialog.Height = 350
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    # Results text box (read-only)
    $rtbResults = New-Object System.Windows.Forms.RichTextBox
    $rtbResults.Location = New-Object System.Drawing.Point(10, 10)
    $rtbResults.Size = New-Object System.Drawing.Size(480, 250)
    $rtbResults.ReadOnly = $true
    $rtbResults.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtbResults.BackColor = [System.Drawing.Color]::White

    # Build results text
    # Show source info if available (from current record test)
    if ($Result.SourceInfo) {
        $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
        $rtbResults.AppendText("SOURCE`r`n")
        $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10)
        $rtbResults.AppendText("  Record:       $($Result.SourceInfo)`r`n")
        if ($Result.TextLength) {
            $rtbResults.AppendText("  Text length:  $($Result.TextLength) characters`r`n")
        }
        $rtbResults.AppendText("`r`n")
    }

    $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $rtbResults.AppendText("PRIMARY SITE`r`n")
    $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10)

    if ($Result.SiteCode) {
        $rtbResults.AppendText("  Code:         $($Result.SiteCode)`r`n")
        $rtbResults.AppendText("  Description:  $($Result.SiteDescription)`r`n")

        $matchTypeDesc = switch ($Result.MatchType) {
            "hard-coded" { "Hard-coded pattern" }
            "melanoma-dict" { "Melanoma dictionary" }
            "standard-dict" { "Standard dictionary" }
            default { $Result.MatchType }
        }
        $rtbResults.AppendText("  Match Type:   $matchTypeDesc`r`n")
        $rtbResults.AppendText("  Matched:      `"$($Result.MatchedPhrase)`"`r`n")
    }
    else {
        $rtbResults.AppendText("  (No match found)`r`n")
    }

    $rtbResults.AppendText("`r`n")
    $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $rtbResults.AppendText("LATERALITY`r`n")
    $rtbResults.SelectionFont = New-Object System.Drawing.Font("Consolas", 10)

    if ($Result.LateralityCode) {
        $rtbResults.AppendText("  Code:         $($Result.LateralityCode)`r`n")
        $rtbResults.AppendText("  Description:  $($Result.LateralityDescription)`r`n")
        $requiresLat = if ($Result.SiteRequiresLaterality) { "Yes" } else { "No" }
        $rtbResults.AppendText("  Site requires laterality: $requiresLat`r`n")
    }
    else {
        $rtbResults.AppendText("  (No site to determine laterality)`r`n")
    }

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Width = 100
    $btnOk.Location = New-Object System.Drawing.Point(280, 270)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = "Copy"
    $btnCopy.Width = 100
    $btnCopy.Location = New-Object System.Drawing.Point(390, 270)
    $btnCopy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($rtbResults.Text)
    })

    $dialog.Controls.AddRange(@($rtbResults, $btnOk, $btnCopy))
    $dialog.AcceptButton = $btnOk

    [void]$dialog.ShowDialog()
}
