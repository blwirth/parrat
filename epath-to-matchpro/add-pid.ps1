# add-pid.ps1
# NAACCR XML patient ID number assignment utilities

. "$PSScriptRoot\xml-helpers.ps1"

function Get-ItemValue {
    param(
        [System.Xml.XmlNode]$Context,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$Id
    )
    
    $node = $Context.SelectSingleNode("./n:Item[@naaccrId='$Id']", $NsMgr)
    if ($node) { return $node.InnerText }
    return ""
}

function Get-PatientIdAssignments {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$Mode = "Default"  # "Default", "OverwriteAll", "ReplaceZeros"
    )

    $report = @()
    $assignments = @{}
    $processedPatients = @{}  # Track which patients we've already processed
    $counter = 0  # Counter for patients that need IDs
    $startValue = 1  # Starting value for IDs

    # Set starting value based on mode
    if ($Mode -eq "ReplaceZeros") {
        $startValue = 90000001
    }

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        if ($null -eq $patient) { continue }

        # Only process each patient once
        if (-not $processedPatients.ContainsKey($patient)) {
            $processedPatients[$patient] = $true

            # Get patient name for display
            $nameLast = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameLast"
            $nameFirst = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameFirst"
            $patientName = "$nameLast, $nameFirst".Trim(', ')

            # Check if patient already has patientIdNumber
            $currentId = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "patientIdNumber"
            $hasId = -not [string]::IsNullOrWhiteSpace($currentId)

            $shouldAssign = $false
            $idValue = ""

            if ($Mode -eq "OverwriteAll") {
                # Overwrite all IDs starting from 1
                $shouldAssign = $true
                $counter++
                $idValue = ($startValue + $counter - 1).ToString("D8")
            }
            elseif ($Mode -eq "ReplaceZeros") {
                # Only replace IDs that are all zeros or empty
                if (-not $hasId -or $currentId -match '^0+$') {
                    $shouldAssign = $true
                    $counter++
                    $idValue = ($startValue + $counter - 1).ToString("D8")
                }
            }
            else {
                # Default mode: only assign if patient doesn't have an ID
                if (-not $hasId) {
                    $shouldAssign = $true
                    $counter++
                    $idValue = $counter.ToString("D8")
                }
            }

            if ($shouldAssign) {
                $report += [PSCustomObject]@{
                    PatientIndex = $counter
                    PatientName  = $patientName
                    CurrentId    = if ([string]::IsNullOrWhiteSpace($currentId)) { "(none)" } else { $currentId }
                    ProposedId   = $idValue
                }

                $assignments[$patient] = $idValue
            }
        }
    }

    return @{
        Report = $report
        Assignments = $assignments
    }
}

function Write-PatientIdXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [hashtable]$Assignments,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath
    )

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

    # Copy root element
    $root    = $XmlDoc.DocumentElement
    $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
    foreach ($attr in $root.Attributes) {
        $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
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

    # Process each Patient
    foreach ($patientNode in $root.SelectNodes("./n:Patient", $NsMgr)) {
        $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)

        # Copy patient attributes
        foreach ($attr in $patientNode.Attributes) {
            $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
            $newAttr.Value = $attr.Value
            [void]$newPatient.Attributes.Append($newAttr)
        }

        # Check if this patient needs a patientIdNumber
        $needsId = $Assignments.ContainsKey($patientNode)
        $patientIdValue = if ($needsId) { $Assignments[$patientNode] } else { $null }

        # Find the first Tumor to determine insertion point
        $tumorsInPatient = $patientNode.SelectNodes("./n:Tumor", $NsMgr)
        $firstTumor = if ($tumorsInPatient.Count -gt 0) { $tumorsInPatient[0] } else { $null }

        # Track if we've added the patientIdNumber
        $patientIdAdded = $false

        # Process child nodes in order
        foreach ($child in $patientNode.ChildNodes) {
            if ($child.LocalName -eq "Item") {
                $idAttr = $child.GetAttribute("naaccrId")
                
                if ($idAttr -eq "patientIdNumber") {
                    # If we need to update it, use the new value; otherwise keep existing
                    if ($needsId) {
                        $imported = $newDoc.ImportNode($child, $true)
                        $imported.InnerText = $patientIdValue
                        [void]$newPatient.AppendChild($imported)
                        $patientIdAdded = $true
                    } else {
                        # Keep existing as-is
                        $imported = $newDoc.ImportNode($child, $true)
                        [void]$newPatient.AppendChild($imported)
                        $patientIdAdded = $true
                    }
                } else {
                    # Regular Item - add it
                    $imported = $newDoc.ImportNode($child, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            } elseif ($child.LocalName -eq "Tumor") {
                # Before adding the first tumor, add patientIdNumber if needed and not already added
                if ($child -eq $firstTumor -and $needsId -and -not $patientIdAdded) {
                    # Create new Item element for patientIdNumber
                    $item = $newDoc.CreateElement("Item", $root.NamespaceURI)
                    $item.SetAttribute("naaccrId", "patientIdNumber")
                    $item.SetAttribute("naaccrNum", "20")
                    $item.InnerText = $patientIdValue
                    [void]$newPatient.AppendChild($item)
                    $patientIdAdded = $true
                }
                
                # Add the tumor
                $imported = $newDoc.ImportNode($child, $true)
                [void]$newPatient.AppendChild($imported)
            }
        }

        # If patient has no tumors and needs ID, add it at the end
        if ($needsId -and -not $patientIdAdded) {
            $item = $newDoc.CreateElement("Item", $root.NamespaceURI)
            $item.SetAttribute("naaccrId", "patientIdNumber")
            $item.SetAttribute("naaccrNum", "20")
            $item.InnerText = $patientIdValue
            [void]$newPatient.AppendChild($item)
        }

        [void]$newRoot.AppendChild($newPatient)
    }

    # Save with formatting to ensure proper indentation and newlines
    $settings                = New-Object System.Xml.XmlWriterSettings
    $settings.Indent         = $true
    $settings.IndentChars    = "  "
    $settings.NewLineChars   = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Show-PatientIdReport {
    param(
        [array]$Report,
        [hashtable]$Assignments,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors
    )

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Patient ID Assignment Report"
    $reportForm.Width = 1000
    $reportForm.Height = 600
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(960, 40)
    $lblSummary.Text = "Patients to update: $($Assignments.Count)"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # DataGridView for report
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 60)
    $grid.Size = New-Object System.Drawing.Size(960, 430)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.SelectionMode = 'FullRowSelect'

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientIndex", [int])
    [void]$table.Columns.Add("PatientName", [string])
    [void]$table.Columns.Add("CurrentId", [string])
    [void]$table.Columns.Add("ProposedId", [string])

    foreach ($item in $Report) {
        $row = $table.NewRow()
        $row["PatientIndex"] = $item.PatientIndex
        $row["PatientName"] = $item.PatientName
        $row["CurrentId"] = if ([string]::IsNullOrWhiteSpace($item.CurrentId)) { "(none)" } else { $item.CurrentId }
        $row["ProposedId"] = $item.ProposedId
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Buttons
    $btnSaveXml = New-Object System.Windows.Forms.Button
    $btnSaveXml.Text = "Save Updated XML"
    $btnSaveXml.Width = 150
    $btnSaveXml.Location = New-Object System.Drawing.Point(10, 510)
    $btnSaveXml.Anchor = 'Bottom,Left'

    $btnSaveCsv = New-Object System.Windows.Forms.Button
    $btnSaveCsv.Text = "Save CSV Report"
    $btnSaveCsv.Width = 150
    $btnSaveCsv.Location = New-Object System.Drawing.Point(170, 510)
    $btnSaveCsv.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(330, 510)
    $btnClose.Anchor = 'Bottom,Left'

    # Save XML button handler
    $btnSaveXml.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-with-patientid.xml")

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
            $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

            Write-PatientIdXml -XmlDoc $XmlDoc -Assignments $Assignments -NsMgr $nsMgr -OutputPath $outputPath

            [System.Windows.Forms.MessageBox]::Show(
                "Updated XML saved to:`n$outputPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving XML: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Save CSV button handler
    $btnSaveCsv.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-patientid-report.csv")

            $Report | Export-Csv -Path $csvPath -NoTypeInformation

            [System.Windows.Forms.MessageBox]::Show(
                "CSV report saved to:`n$csvPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving CSV: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Close button handler
    $btnClose.Add_Click({
        $reportForm.Close()
    })

    # Add controls to form
    $reportForm.Controls.AddRange(@($lblSummary, $grid, $btnSaveXml, $btnSaveCsv, $btnClose))

    [void]$reportForm.ShowDialog()
}
