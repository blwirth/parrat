function Build-SearchIndex {
    param(
        [string]$FileType,
        [hashtable]$ScriptVars
    )

    try {
        if ($FileType -eq 'xml') {
            $tumors = $ScriptVars['Tumors']
            $nsMgr = $ScriptVars['NsMgr']
            if (-not $tumors -or $tumors.Count -eq 0) { return @() }

            $index = New-Object string[] $tumors.Count

            for ($i = 0; $i -lt $tumors.Count; $i++) {
                $parts = [System.Collections.Generic.List[string]]::new()
                $tumor = $tumors[$i]

                # Walk up to Patient node
                $patient = $tumor.ParentNode
                while ($null -ne $patient -and $patient.LocalName -ne "Patient") {
                    $patient = $patient.ParentNode
                }

                # Patient-level items
                if ($null -ne $patient) {
                    foreach ($item in $patient.SelectNodes("./n:Item", $nsMgr)) {
                        $text = $item.InnerText
                        if (-not [string]::IsNullOrEmpty($text)) {
                            $parts.Add($text)
                        }
                    }
                }

                # Tumor-level items (including text fields)
                foreach ($item in $tumor.SelectNodes("./n:Item", $nsMgr)) {
                    $text = $item.InnerText
                    if (-not [string]::IsNullOrEmpty($text)) {
                        $parts.Add($text)
                    }
                }

                $index[$i] = ($parts -join " ").ToLower()
            }

            return $index
        }
        elseif ($FileType -eq 'hl7') {
            $messages = $ScriptVars['Hl7Messages']
            if (-not $messages -or $messages.Count -eq 0) { return @() }

            $index = New-Object string[] $messages.Count

            for ($i = 0; $i -lt $messages.Count; $i++) {
                $msg = $messages[$i]
                $parts = [System.Collections.Generic.List[string]]::new()

                # Add parsed fields
                foreach ($prop in @('PatientId', 'PatientLastName', 'PatientFirstName',
                                    'DateOfBirth', 'Sex', 'MessageType',
                                    'SendingApplication', 'SendingFacility',
                                    'OrderDateTime', 'OrderingProvider')) {
                    $val = $msg.$prop
                    if (-not [string]::IsNullOrEmpty($val)) {
                        $parts.Add($val)
                    }
                }

                # OBX text content
                $obxSegs = if ($msg.Segments -and $msg.Segments.ContainsKey("OBX")) { $msg.Segments["OBX"] } else { $null }
                if ($obxSegs -and $obxSegs.Count -gt 0) {
                    $obxText = Get-ObxTextContent -ObxSegments $obxSegs
                    if (-not [string]::IsNullOrEmpty($obxText)) {
                        $parts.Add($obxText)
                    }
                }

                $index[$i] = ($parts -join " ").ToLower()
            }

            return $index
        }
        else {
            return @()
        }
    }
    catch {
        Write-ParatError -Message "Failed to build search index" -Action "SEARCH_INDEX" -ErrorRecord $_
        return @()
    }
}

function Invoke-SearchFilter {
    param(
        [string]$SearchText,
        [System.Data.DataTable]$NavTable,
        [string[]]$SearchIndex
    )

    $totalCount = if ($null -ne $SearchIndex) { $SearchIndex.Count } else { 0 }

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        if ($null -ne $NavTable) {
            $NavTable.DefaultView.RowFilter = ""
        }
        return $totalCount
    }

    $lowerSearch = $SearchText.ToLower()
    $matchingIndices = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $SearchIndex.Count; $i++) {
        if ($SearchIndex[$i].Contains($lowerSearch)) {
            $matchingIndices.Add($i + 1)  # 1-based Index column
        }
    }

    try {
        if ($matchingIndices.Count -eq 0) {
            $NavTable.DefaultView.RowFilter = "Index = -1"
        }
        else {
            $NavTable.DefaultView.RowFilter = "Index IN ({0})" -f ($matchingIndices -join ",")
        }
    }
    catch {
        Write-ParatError -Message "Failed to apply search filter" -Action "SEARCH_FILTER" -ErrorRecord $_
    }

    return $matchingIndices.Count
}

function Invoke-SearchHighlight {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$SearchText
    )

    if ($null -eq $RichTextBox -or $RichTextBox.TextLength -eq 0) { return }

    # Clear previous highlights
    $RichTextBox.SelectAll()
    $RichTextBox.SelectionBackColor = $RichTextBox.BackColor
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0

    if ([string]::IsNullOrWhiteSpace($SearchText)) { return }

    $yellow = [System.Drawing.Color]::Yellow
    $text = $RichTextBox.Text
    $lower = $text.ToLower()
    $needle = $SearchText.ToLower()
    $needleLen = $needle.Length
    $pos = 0

    while ($true) {
        $pos = $lower.IndexOf($needle, $pos)
        if ($pos -lt 0) { break }

        $RichTextBox.Select($pos, $needleLen)
        $RichTextBox.SelectionBackColor = $yellow
        $pos += $needleLen
    }

    # Reset selection
    $RichTextBox.SelectionStart = 0
    $RichTextBox.SelectionLength = 0
}
