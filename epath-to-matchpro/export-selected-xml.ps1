function Export-SelectedXml {
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath
    )

    if ($TumorIndices.Count -eq 0) {
        return @{ Success = $false; Message = "No tumors selected for export." }
    }

    $root = $XmlDoc.DocumentElement
    $errors = @()

    try {
        # Create new XML document
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

        # Copy root element with all attributes
        $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
        foreach ($attr in $root.Attributes) {
            $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
            $newAttr.Value = $attr.Value
            [void]$newRoot.Attributes.Append($newAttr)
        }
        [void]$newDoc.AppendChild($newRoot)

        # Copy non-Patient children of root
        foreach ($child in $root.ChildNodes) {
            if ($child.LocalName -ne "Patient") {
                $imported = $newDoc.ImportNode($child, $true)
                [void]$newRoot.AppendChild($imported)
            }
        }

        # Group tumors by patient
        $patientsMap = @{}  # Patient node -> array of tumor indices

        foreach ($tumorIndex in $TumorIndices) {
            if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) {
                $errors += "Invalid tumor index: $tumorIndex"
                continue
            }

            $tumor = $script:Tumors[$tumorIndex]
            $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

            if ($null -eq $patient) {
                $errors += "Tumor at index $tumorIndex has no parent Patient node"
                continue
            }

            if (-not $patientsMap.ContainsKey($patient)) {
                $patientsMap[$patient] = @()
            }
            $patientsMap[$patient] += $tumorIndex
        }

        # Process each patient and add their checked tumors
        foreach ($patientNode in $patientsMap.Keys) {
            $tumorIndicesForPatient = $patientsMap[$patientNode]

            # Create new Patient element
            $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)

            # Copy patient attributes
            foreach ($attr in $patientNode.Attributes) {
                $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
                $newAttr.Value = $attr.Value
                [void]$newPatient.Attributes.Append($newAttr)
            }

            # Copy patient-level Items
            foreach ($child in $patientNode.ChildNodes) {
                if ($child.LocalName -eq "Item") {
                    $imported = $newDoc.ImportNode($child, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }

            # Add all checked tumors for this patient
            foreach ($tumorIndex in $tumorIndicesForPatient) {
                $tumor = $script:Tumors[$tumorIndex]
                $importedTumor = $newDoc.ImportNode($tumor, $true)
                [void]$newPatient.AppendChild($importedTumor)
            }

            [void]$newRoot.AppendChild($newPatient)
        }

        # Save with formatting
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.IndentChars = "  "
        $settings.NewLineChars = "`r`n"
        $settings.NewLineHandling = "Replace"

        $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
        $newDoc.Save($writer)
        $writer.Close()

        return @{
            Success = ($errors.Count -eq 0)
            ExportedCount = $TumorIndices.Count
            Errors = $errors
        }
    }
    catch {
        return @{
            Success = $false
            ExportedCount = 0
            Errors = @("Error during export: $($_.Exception.Message)")
        }
    }
}
