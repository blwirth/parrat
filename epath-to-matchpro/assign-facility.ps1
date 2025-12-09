# assign-facility.ps1
# NAACCR XML facility number assignment utilities

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

function Get-FacilityFromFilename {
    param([string]$FilePath)
    
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    
    # Look for 7-digit number in filename
    $match = [regex]::Match($fileName, '(?<![0-9])\d{7}(?![0-9])')
    
    if ($match.Success) {
        $facilityNum = $match.Value
        # Left-pad to 10 digits
        return $facilityNum.PadLeft(10, '0')
    }
    
    return $null
}

function Get-FacilityAssignments {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$FacilityNumber
    )

    $report = @()
    $assignments = @{}

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        # Get patient name for display
        $nameLast = ""
        $nameFirst = ""
        if ($patient -ne $null) {
            $nameLast = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameLast"
            $nameFirst = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameFirst"
        }
        $patientName = "$nameLast, $nameFirst".Trim(', ')

        # Get current reportingFacility value
        $currentFacility = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "reportingFacility").Trim()

        # Check if it's blank or all zeros
        $needsUpdate = [string]::IsNullOrWhiteSpace($currentFacility) -or ($currentFacility -match '^0+$')

        if ($needsUpdate) {
            $report += [PSCustomObject]@{
                TumorIndex       = $i + 1
                PatientName      = $patientName
                CurrentFacility  = $currentFacility
                ProposedFacility = $FacilityNumber
            }

            $assignments[$i] = $FacilityNumber
        }
    }

    return @{
        Report = $report
        Assignments = $assignments
    }
}

function Write-FacilityAssignedXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
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

        # Copy patient-level Items
        foreach ($child in $patientNode.ChildNodes) {
            if ($child.LocalName -eq "Item") {
                $imported = $newDoc.ImportNode($child, $true)
                [void]$newPatient.AppendChild($imported)
            }
        }

        # Process tumors
        $tumorsInPatient = $patientNode.SelectNodes("./n:Tumor", $NsMgr)
        
        foreach ($tumor in $tumorsInPatient) {
            # Find this tumor's index in the global list
            $tumorIndex = -1
            for ($i = 0; $i -lt $Tumors.Count; $i++) {
                if ($Tumors[$i] -eq $tumor) {
                    $tumorIndex = $i
                    break
                }
            }

            # Clone the tumor
            $newTumor = $newDoc.ImportNode($tumor, $true)

            # Apply facility assignment if this tumor has one
            if ($tumorIndex -ge 0 -and $Assignments.ContainsKey($tumorIndex)) {
                $facilityNum = $Assignments[$tumorIndex]
                
                $facilityNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", $NsMgr)
                if ($facilityNode) {
                    $facilityNode.InnerText = $facilityNum
                }
                else {
                    # Create new Item element
                    $facilityNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                    $attr = $newDoc.CreateAttribute("naaccrId")
                    $attr.Value = "reportingFacility"
                    [void]$facilityNode.Attributes.Append($attr)
                    $facilityNode.InnerText = $facilityNum
                    [void]$newTumor.AppendChild($facilityNode)
                }
            }

            [void]$newPatient.AppendChild($newTumor)
        }

        [void]$newRoot.AppendChild($newPatient)
    }

    # Save with formatting
    $settings                = New-Object System.Xml.XmlWriterSettings
    $settings.Indent         = $true
    $settings.NewLineChars   = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Show-FacilityAssignmentReport {
    param(
        [array]$Report,
        [hashtable]$Assignments,
        [string]$FacilityNumber,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors
    )

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Facility Number Assignment Report"
    $reportForm.Width = 1000
    $reportForm.Height = 600
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(960, 40)
    $lblSummary.Text = "Tumors to update: $($Assignments.Count) | Facility Number: $FacilityNumber"
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
    [void]$table.Columns.Add("TumorIndex", [int])
    [void]$table.Columns.Add("PatientName", [string])
    [void]$table.Columns.Add("CurrentFacility", [string])
    [void]$table.Columns.Add("ProposedFacility", [string])

    foreach ($item in $Report) {
        $row = $table.NewRow()
        $row["TumorIndex"] = $item.TumorIndex
        $row["PatientName"] = $item.PatientName
        $row["CurrentFacility"] = $item.CurrentFacility
        $row["ProposedFacility"] = $item.ProposedFacility
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
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-facility.xml")

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
            $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

            Write-FacilityAssignedXml -XmlDoc $XmlDoc -Tumors $Tumors -Assignments $Assignments -NsMgr $nsMgr -OutputPath $outputPath

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
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-facility-report.csv")

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