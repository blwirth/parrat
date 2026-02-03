function Get-UniqueNaaccrIds {
    <#
    .SYNOPSIS
        Scans loaded XML and returns all unique NAACCR variable IDs with metadata.
    .PARAMETER XmlDoc
        The loaded XmlDocument.
    .PARAMETER NsMgr
        The XmlNamespaceManager for the document.
    #>
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    Initialize-NaaccrDictionary | Out-Null

    # Hashtable: naaccrId -> @{ Count; Levels (HashSet of strings) }
    $idMap = @{}

    $root = $XmlDoc.DocumentElement

    # NaaccrData-level Items
    foreach ($item in $root.ChildNodes) {
        if ($item.LocalName -eq 'Item') {
            $naaccrId = $item.GetAttribute('naaccrId')
            if ([string]::IsNullOrEmpty($naaccrId)) { continue }
            if (-not $idMap.ContainsKey($naaccrId)) {
                $idMap[$naaccrId] = @{ Count = 0; Levels = New-Object 'System.Collections.Generic.HashSet[string]' }
            }
            $idMap[$naaccrId].Count++
            [void]$idMap[$naaccrId].Levels.Add('NaaccrData')
        }
    }

    # Patient and Tumor level Items
    foreach ($child in $root.ChildNodes) {
        if ($child.LocalName -ne 'Patient') { continue }

        # Patient-level Items
        foreach ($pChild in $child.ChildNodes) {
            if ($pChild.LocalName -eq 'Item') {
                $naaccrId = $pChild.GetAttribute('naaccrId')
                if ([string]::IsNullOrEmpty($naaccrId)) { continue }
                if (-not $idMap.ContainsKey($naaccrId)) {
                    $idMap[$naaccrId] = @{ Count = 0; Levels = New-Object 'System.Collections.Generic.HashSet[string]' }
                }
                $idMap[$naaccrId].Count++
                [void]$idMap[$naaccrId].Levels.Add('Patient')
            }
            elseif ($pChild.LocalName -eq 'Tumor') {
                # Tumor-level Items
                foreach ($tChild in $pChild.ChildNodes) {
                    if ($tChild.LocalName -eq 'Item') {
                        $naaccrId = $tChild.GetAttribute('naaccrId')
                        if ([string]::IsNullOrEmpty($naaccrId)) { continue }
                        if (-not $idMap.ContainsKey($naaccrId)) {
                            $idMap[$naaccrId] = @{ Count = 0; Levels = New-Object 'System.Collections.Generic.HashSet[string]' }
                        }
                        $idMap[$naaccrId].Count++
                        [void]$idMap[$naaccrId].Levels.Add('Tumor')
                    }
                }
            }
        }
    }

    # Build result array enriched with dictionary display names
    $results = @()
    foreach ($key in $idMap.Keys) {
        $entry = $idMap[$key]
        $dictItem = Get-NaaccrItemByXmlId -XmlId $key
        if ($null -ne $dictItem) {
            $displayName = $dictItem.Name
        } else {
            $displayName = "$key (custom)"
        }
        $levelsStr = ($entry.Levels | Sort-Object) -join ', '
        $results += [PSCustomObject]@{
            XmlId       = $key
            DisplayName = $displayName
            Count       = $entry.Count
            Levels      = $levelsStr
        }
    }

    return $results | Sort-Object DisplayName
}

function Remove-XmlVariable {
    <#
    .SYNOPSIS
        Creates a new XML file with all occurrences of a NAACCR variable removed.
    .PARAMETER XmlDoc
        The source XmlDocument.
    .PARAMETER NaaccrIds
        One or more naaccrId attribute values to remove.
    .PARAMETER OutputPath
        Path for the output XML file.
    #>
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [string[]]$NaaccrIds,
        [string]$OutputPath
    )

    # Create new document and deep-clone the source
    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Copy XML declaration
    $declNode = $XmlDoc.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlDeclaration] } |
        Select-Object -First 1
    if ($declNode) {
        $newDecl = $newDoc.CreateXmlDeclaration($declNode.Version, $declNode.Encoding, $declNode.Standalone)
        [void]$newDoc.AppendChild($newDecl)
    }

    # Deep clone the document element
    $imported = $newDoc.ImportNode($XmlDoc.DocumentElement, $true)
    [void]$newDoc.AppendChild($imported)

    # Set up namespace manager on the new document
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($newDoc.NameTable)
    $ns = $newDoc.DocumentElement.NamespaceURI
    if (-not [string]::IsNullOrEmpty($ns)) {
        $nsMgr.AddNamespace('n', $ns)
    }

    # Find and remove all Item elements with matching naaccrIds
    $removedCount = 0
    foreach ($id in $NaaccrIds) {
        $nodes = $newDoc.SelectNodes("//n:Item[@naaccrId='$id']", $nsMgr)
        foreach ($node in $nodes) {
            [void]$node.ParentNode.RemoveChild($node)
            $removedCount++
        }
    }

    # Save with formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $writer = $null
    try {
        $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
        $newDoc.Save($writer)
    }
    finally {
        if ($null -ne $writer) {
            $writer.Close()
        }
    }

    return @{
        RemovedCount = $removedCount
        OutputPath   = $OutputPath
    }
}

function Show-CopyableErrorDialog {
    <#
    .SYNOPSIS
        Shows an error dialog with copyable details text.
    .PARAMETER Message
        The main error message (shown in bold).
    .PARAMETER Details
        The detailed error text (shown in a copyable text box).
    .PARAMETER Title
        The dialog title.
    #>
    param(
        [string]$Message,
        [string]$Details,
        [string]$Title = "Error"
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(500, 350)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimumSize = New-Object System.Drawing.Size(400, 250)

    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Text = $Message
    $lblMessage.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblMessage.Location = New-Object System.Drawing.Point(12, 12)
    $lblMessage.Size = New-Object System.Drawing.Size(460, 40)
    $lblMessage.Anchor = 'Top,Left,Right'

    $txtDetails = New-Object System.Windows.Forms.TextBox
    $txtDetails.Multiline = $true
    $txtDetails.ReadOnly = $true
    $txtDetails.ScrollBars = 'Both'
    $txtDetails.WordWrap = $false
    $txtDetails.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtDetails.Text = $Details
    $txtDetails.Location = New-Object System.Drawing.Point(12, 56)
    $txtDetails.Size = New-Object System.Drawing.Size(460, 200)
    $txtDetails.Anchor = 'Top,Bottom,Left,Right'

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = "Copy All"
    $btnCopy.Size = New-Object System.Drawing.Size(80, 28)
    $btnCopy.Location = New-Object System.Drawing.Point(310, 268)
    $btnCopy.Anchor = 'Bottom,Right'
    $btnCopy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText("$Message`r`n`r`n$Details")
    })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Size = New-Object System.Drawing.Size(80, 28)
    $btnClose.Location = New-Object System.Drawing.Point(396, 268)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $btnClose

    $dlg.Controls.AddRange(@($lblMessage, $txtDetails, $btnCopy, $btnClose))

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}
