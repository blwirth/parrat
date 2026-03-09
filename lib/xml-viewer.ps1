function Show-RawXmlForTumor {
    param(
        [int]$Index
    )

    if (-not $script:XmlDoc) {
        [System.Windows.Forms.MessageBox]::Show("No XML document loaded.", "Show XML")
        return
    }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
        [System.Windows.Forms.MessageBox]::Show("Index out of range.", "Show XML")
        return
    }

    $origDoc = $script:XmlDoc
    $root    = $origDoc.DocumentElement
    if (-not $root) {
        [System.Windows.Forms.MessageBox]::Show("Root <NaaccrData> element not found.", "Show XML")
        return
    }

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    if (-not $patient) {
        [System.Windows.Forms.MessageBox]::Show("Patient node for selected tumor not found.", "Show XML")
        return
    }

    # Build a new minimal NAACCR document:
    # - same <NaaccrData> element name/ns and attributes
    # - all non-Patient children (root-level Item nodes, etc.)
    # - only the selected Patient subtree

    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Create NaaccrData root with same name/ns/attributes
    $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
    foreach ($attr in $root.Attributes) {
        $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
        $newAttr.Value = $attr.Value
        [void]$newRoot.Attributes.Append($newAttr)
    }
    [void]$newDoc.AppendChild($newRoot)

    # Copy top-level non-Patient children (e.g. root-level Item nodes)
    foreach ($child in $root.ChildNodes) {
        if ($child.LocalName -eq "Patient") { continue }
        $imported = $newDoc.ImportNode($child, $true)
        [void]$newRoot.AppendChild($imported)
    }

    # Import only the selected Patient subtree
    $importedPatient = $newDoc.ImportNode($patient, $true)
    [void]$newRoot.AppendChild($importedPatient)

    # Serialize new document; reuse original XML declaration if present
    $bodyXml = $newDoc.OuterXml

    $declNode = $origDoc.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlDeclaration] } |
        Select-Object -First 1

    if ($declNode) {
        $finalXml = $declNode.OuterXml + "`r`n" + $bodyXml
    }
    else {
        $finalXml = $bodyXml
    }

    $finalXml = Format-Xml -Xml $finalXml

    $label = Get-TumorLabel -Index $Index

    $xmlForm = New-Object System.Windows.Forms.Form
    $xmlForm.Text   = "Raw XML - $label"
    $xmlForm.Width  = 1400
    $xmlForm.Height = 900
    $xmlForm.StartPosition = "CenterScreen"

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = 'Fill'
    $rtb.ReadOnly = $true
    $rtb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $rtb.WordWrap = $false
    $rtb.ScrollBars = "Both"

    # Apply syntax highlighting
    Set-XmlSyntaxHighlighting -RichTextBox $rtb -XmlText $finalXml

    $xmlForm.Controls.Add($rtb)
    [void]$xmlForm.ShowDialog()
}