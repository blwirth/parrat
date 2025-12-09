# deduplicate.ps1
# NAACCR XML deduplication utilities

. "$PSScriptRoot\xml-helpers.ps1"

function Get-PatientTumorGroups {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $groups = @{}

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        $nameLast = ""
        $nameFirst = ""
        $dateOfBirth = ""
        $dateOfDiagnosis = ""

        if ($patient -ne $null) {
            $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
            $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
            $dobNode = $patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $NsMgr)

            if ($nlNode) { $nameLast = $nlNode.InnerText }
            if ($nfNode) { $nameFirst = $nfNode.InnerText }
            if ($dobNode) { $dateOfBirth = $dobNode.InnerText }
        }

        $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $NsMgr)
        if ($dxNode) { $dateOfDiagnosis = $dxNode.InnerText }

        # Create patient key
        $key = "$nameLast|$nameFirst|$dateOfBirth|$dateOfDiagnosis"

        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @()
        }

        # Store tumor index and node
        $groups[$key] += @{
            Index = $i
            Tumor = $tumor
            Patient = $patient
        }
    }

    return $groups
}

function Get-TumorFingerprint {
    param(
        [System.Xml.XmlNode]$Tumor,
        [System.Xml.XmlNode]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    # Fields to ignore in comparison
    $ignoredFields = @(
        'dateCaseReportReceived',
        'pathDateSpecCollect1',
        'pathDateSpecCollect2',
        'pathDateSpecCollect3',
        'pathDateSpecCollect4',
        'physician3'
    )

    $items = @()

    # Patient items
    if ($Patient -ne $null) {
        $pItems = $Patient.SelectNodes("./n:Item", $NsMgr)
        foreach ($item in $pItems) {
            $id = $item.GetAttribute("naaccrId")
            $val = $item.InnerText
            
            if ($ignoredFields -notcontains $id) {
                $items += "P|$id|$val"
            }
        }
    }

    # Tumor items
    $tItems = $Tumor.SelectNodes("./n:Item", $NsMgr)
    foreach ($item in $tItems) {
        $id = $item.GetAttribute("naaccrId")
        $val = $item.InnerText

        # For date-time fields, only compare date portion (first 8 chars)
        if ($id -match '^pathDateSpecCollect[1-4]$' -and $val.Length -ge 8) {
            $val = $val.Substring(0, 8)
        }

        if ($ignoredFields -notcontains $id) {
            $items += "T|$id|$val"
        }
    }

    # Sort and join to create fingerprint
    $items = $items | Sort-Object
    return ($items -join "||")
}

function Get-TiebreakerValue {
    param(
        [System.Xml.XmlNode]$Tumor,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$FieldId
    )

    $node = $Tumor.SelectSingleNode("./n:Item[@naaccrId='$FieldId']", $NsMgr)
    if ($node) {
        return $node.InnerText
    }
    return ""
}

function Apply-TiebreakerRules {
    param(
        [array]$DuplicateGroup,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    if ($DuplicateGroup.Count -eq 1) {
        return $DuplicateGroup[0]
    }

    # Rule 1: Keep earliest dateCaseReportReceived (primary rule)
    $withDates = $DuplicateGroup | Where-Object {
        $date = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
        -not [string]::IsNullOrWhiteSpace($date)
    } | Sort-Object {
        Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
    }

    if ($withDates.Count -gt 0) {
        $candidates = @($withDates[0])
        $earliestDate = Get-TiebreakerValue -Tumor $withDates[0].Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
        
        # Get all with same earliest date
        for ($i = 1; $i -lt $withDates.Count; $i++) {
            $date = Get-TiebreakerValue -Tumor $withDates[$i].Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
            if ($date -eq $earliestDate) {
                $candidates += $withDates[$i]
            } else {
                break
            }
        }

        # If multiple with same date, apply Rule 2
        if ($candidates.Count -gt 1) {
            # Rule 2: Prefer non-empty physician3
            $withPhysician = $candidates | Where-Object {
                $phys = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'physician3'
                -not [string]::IsNullOrWhiteSpace($phys)
            }

            if ($withPhysician.Count -gt 0) {
                return $withPhysician[0]
            }
        }

        return $candidates[0]
    }

    # No dates found, try Rule 2
    $withPhysician = $DuplicateGroup | Where-Object {
        $phys = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'physician3'
        -not [string]::IsNullOrWhiteSpace($phys)
    }

    if ($withPhysician.Count -gt 0) {
        return $withPhysician[0]
    }

    # Rule 3: Keep first occurrence (fallback)
    return $DuplicateGroup[0]
}

function Find-Duplicates {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    Write-Host "Grouping tumors by patient identifiers..."
    $patientGroups = Get-PatientTumorGroups -Tumors $Tumors -NsMgr $NsMgr

    $duplicateReport = @()
    $indicesToKeep = @{}

    $groupNum = 0
    foreach ($key in $patientGroups.Keys) {
        $group = $patientGroups[$key]
        $groupNum++

        if ($group.Count -le 1) {
            # No duplicates in this group
            $indicesToKeep[$group[0].Index] = $true
            continue
        }

        Write-Host "Processing patient group $groupNum : $key (${$group.Count} tumors)"

        # Build fingerprints for this group
        $fingerprintGroups = @{}

        foreach ($item in $group) {
            $fingerprint = Get-TumorFingerprint -Tumor $item.Tumor -Patient $item.Patient -NsMgr $NsMgr

            if (-not $fingerprintGroups.ContainsKey($fingerprint)) {
                $fingerprintGroups[$fingerprint] = @()
            }

            $fingerprintGroups[$fingerprint] += $item
        }

        # Process each fingerprint group
        foreach ($fingerprint in $fingerprintGroups.Keys) {
            $dupGroup = $fingerprintGroups[$fingerprint]

            if ($dupGroup.Count -eq 1) {
                # Not a duplicate
                $indicesToKeep[$dupGroup[0].Index] = $true
            }
            else {
                # Found duplicates - apply tiebreaker
                $winner = Apply-TiebreakerRules -DuplicateGroup $dupGroup -NsMgr $NsMgr
                $indicesToKeep[$winner.Index] = $true

                # Build report entry
                $allIndices = ($dupGroup | ForEach-Object { $_.Index + 1 }) -join ","
                $removedIndices = ($dupGroup | Where-Object { $_.Index -ne $winner.Index } | ForEach-Object { $_.Index + 1 }) -join ","

                $dateReceived = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
                $physician3 = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'physician3'

                $reason = "Duplicate detected"
                if (-not [string]::IsNullOrWhiteSpace($dateReceived)) {
                    $reason = "Earliest dateCaseReportReceived"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($physician3)) {
                    $reason = "Non-empty physician3"
                }
                else {
                    $reason = "First occurrence"
                }

                $duplicateReport += [PSCustomObject]@{
                    PatientKey = $key
                    AllIndices = $allIndices
                    KeptIndex = $winner.Index + 1
                    RemovedIndices = $removedIndices
                    Reason = $reason
                    DateReceived = $dateReceived
                    Physician3 = $physician3
                }
            }
        }
    }

    return @{
        IndicesToKeep = $indicesToKeep
        Report = $duplicateReport
    }
}

function Write-DedupedXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [hashtable]$IndicesToKeep,
        [string]$OutputPath
    )

    # Create new document with same structure
    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Copy XML declaration if present
    $declNode = $XmlDoc.ChildNodes | Where-Object { $_ -is [System.Xml.XmlDeclaration] } | Select-Object -First 1
    if ($declNode) {
        $newDecl = $newDoc.CreateXmlDeclaration($declNode.Version, $declNode.Encoding, $declNode.Standalone)
        [void]$newDoc.AppendChild($newDecl)
    }

    # Copy root element with attributes
    $root = $XmlDoc.DocumentElement
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

    # Build set of kept tumor nodes
    $keptTumorNodes = @{}
    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        if ($IndicesToKeep.ContainsKey($i)) {
            $keptTumorNodes[$Tumors[$i]] = $true
        }
    }

    # Copy Patient nodes that contain kept tumors
    foreach ($patientNode in $root.SelectNodes("//n:Patient", $XmlDoc.CreateNavigator().GetNamespace(""))) {
        $tumorsInPatient = $patientNode.SelectNodes("./n:Tumor", $XmlDoc.CreateNavigator().GetNamespace(""))
        
        # Check if this patient has any kept tumors
        $hasKeptTumor = $false
        foreach ($tumor in $tumorsInPatient) {
            if ($keptTumorNodes.ContainsKey($tumor)) {
                $hasKeptTumor = $true
                break
            }
        }

        if ($hasKeptTumor) {
            # Import the patient node
            $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)
            
            # Copy patient attributes
            foreach ($attr in $patientNode.Attributes) {
                $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
                $newAttr.Value = $attr.Value
                [void]$newPatient.Attributes.Append($newAttr)
            }

            # Copy patient-level Item nodes
            foreach ($child in $patientNode.ChildNodes) {
                if ($child.LocalName -eq "Item") {
                    $imported = $newDoc.ImportNode($child, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }

            # Copy only kept tumors
            foreach ($tumor in $tumorsInPatient) {
                if ($keptTumorNodes.ContainsKey($tumor)) {
                    $imported = $newDoc.ImportNode($tumor, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }

            [void]$newRoot.AppendChild($newPatient)
        }
    }

    # Save formatted XML
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Show-DeduplicationReport {
    param(
        [array]$Report,
        [hashtable]$IndicesToKeep,
        [int]$OriginalCount,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors
    )

    $dedupedCount = $IndicesToKeep.Count
    $removedCount = $OriginalCount - $dedupedCount

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Deduplication Report"
    $reportForm.Width = 1400
    $reportForm.Height = 700
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Original tumors: $OriginalCount | Kept: $dedupedCount | Removed: $removedCount duplicates"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # DataGridView for report
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(10, 60)
    $grid.Size = New-Object System.Drawing.Size(1360, 500)
    $grid.Anchor = 'Top,Left,Right,Bottom'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "Fill"

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientKey", [string])
    [void]$table.Columns.Add("AllIndices", [string])
    [void]$table.Columns.Add("KeptIndex", [string])
    [void]$table.Columns.Add("RemovedIndices", [string])
    [void]$table.Columns.Add("Reason", [string])
    [void]$table.Columns.Add("DateReceived", [string])
    [void]$table.Columns.Add("Physician3", [string])

    foreach ($item in $Report) {
        $row = $table.NewRow()
        $row["PatientKey"] = $item.PatientKey
        $row["AllIndices"] = $item.AllIndices
        $row["KeptIndex"] = $item.KeptIndex
        $row["RemovedIndices"] = $item.RemovedIndices
        $row["Reason"] = $item.Reason
        $row["DateReceived"] = $item.DateReceived
        $row["Physician3"] = $item.Physician3
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # Buttons
    $btnSaveXml = New-Object System.Windows.Forms.Button
    $btnSaveXml.Text = "Save Deduped XML"
    $btnSaveXml.Width = 150
    $btnSaveXml.Location = New-Object System.Drawing.Point(10, 580)
    $btnSaveXml.Anchor = 'Bottom,Left'

    $btnSaveCsv = New-Object System.Windows.Forms.Button
    $btnSaveCsv.Text = "Save CSV Report"
    $btnSaveCsv.Width = 150
    $btnSaveCsv.Location = New-Object System.Drawing.Point(170, 580)
    $btnSaveCsv.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(330, 580)
    $btnClose.Anchor = 'Bottom,Left'

    # Save XML button handler
    $btnSaveXml.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-dedup.xml")

            Write-DedupedXml -XmlDoc $XmlDoc -Tumors $Tumors -IndicesToKeep $IndicesToKeep -OutputPath $outputPath

            [System.Windows.Forms.MessageBox]::Show(
                "Deduplicated XML saved to:`n$outputPath",
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
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-dedup-report.csv")

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
