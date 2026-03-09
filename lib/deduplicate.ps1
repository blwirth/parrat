# deduplicate.ps1
# NAACCR XML deduplication utilities

. "$PSScriptRoot\syntax-helpers.ps1"

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
		$pathReportNumber1 = ""

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
		
		$dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $NsMgr)
        if ($dxNode) { $pathReportNumber1 = $dxNode.InnerText }

        # Create patient key
        $key = "$nameLast|$nameFirst|$dateOfBirth|$dateOfDiagnosis|$pathReportNumber1"

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
		'dateCaseReportLoaded',
		'dateCaseReportExported',
        'pathDateSpecCollect1',
        'pathDateSpecCollect2',
        'pathDateSpecCollect3',
        'pathDateSpecCollect4',
		'pathDateSpecCollect5',
        'physician3',
		'physicianManaging',
		'physicianFollowUp'
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
	
	# New Rule 1: If there is any dateCaseReportLoaded, keep earliest
    $withLoaded = @($DuplicateGroup | Where-Object {
        $loadDate = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportLoaded'
        -not [string]::IsNullOrWhiteSpace($loadDate)
    } | Sort-Object {
        Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportLoaded'
    })

    if ($withLoaded.Count -gt 0) {
        return $withLoaded[0]
    }

    # Rule 2: Keep earliest dateCaseReportReceived (primary rule)
    $withDates = @($DuplicateGroup | Where-Object {
        $date = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
        -not [string]::IsNullOrWhiteSpace($date)
    } | Sort-Object {
        Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
    })

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

        # If multiple with same date, apply Rule 3
        if ($candidates.Count -gt 1) {
            # Rule 3: Prefer non-empty physician3
            $withPhysician = @($candidates | Where-Object {
                $phys = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'physician3'
                -not [string]::IsNullOrWhiteSpace($phys)
            })

            if ($withPhysician.Count -gt 0) {
                return $withPhysician[0]
            }
        }

        return $candidates[0]
    }

    # No dates found, try Rule 3
    $withPhysician = @($DuplicateGroup | Where-Object {
        $phys = Get-TiebreakerValue -Tumor $_.Tumor -NsMgr $NsMgr -FieldId 'physician3'
        -not [string]::IsNullOrWhiteSpace($phys)
    })

    if ($withPhysician.Count -gt 0) {
        return $withPhysician[0]
    }

    # Rule 4: Keep first occurrence (fallback)
    return $DuplicateGroup[0]
}

function Get-Duplicates {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    Write-Host "Grouping tumors by patient identifiers..."
    $patientGroups    = Get-PatientTumorGroups -Tumors $Tumors -NsMgr $NsMgr
    $duplicateReport  = @()
    $indicesToKeep    = @{}

    $groupNum = 0

    foreach ($key in $patientGroups.Keys) {
        $group = $patientGroups[$key]
        $groupNum++

        if (-not $group -or $group.Count -eq 0) {
            # Defensive: nothing to keep
            Write-Host "Group $groupNum ($key): empty group, skipping."
            continue
        }

        if ($group.Count -eq 1) {
            # No duplicates in this patient group; keep all entries
            foreach ($item in $group) {
                if ($null -eq $item) { continue }
                if ($null -eq $item.Index) {
                    Write-Warning "Group $groupNum ($key): item with null Index in single-entry group; skipping."
                    continue
                }
                $indicesToKeep[$item.Index] = $true
            }
            continue
        }

        Write-Host "Processing patient group $groupNum : $key ($($group.Count) tumors)"

        # Build fingerprints for this patient group
        $fingerprintGroups = @{}

        foreach ($item in $group) {
            if ($null -eq $item) {
                Write-Warning "Group $groupNum ($key): encountered null item; skipping."
                continue
            }

            $fingerprint = Get-TumorFingerprint -Tumor $item.Tumor -Patient $item.Patient -NsMgr $NsMgr

            if (-not $fingerprintGroups.ContainsKey($fingerprint)) {
                $fingerprintGroups[$fingerprint] = @()
            }

            $fingerprintGroups[$fingerprint] += $item
        }

        foreach ($fingerprint in $fingerprintGroups.Keys) {
            $dupGroup = $fingerprintGroups[$fingerprint]

            if (-not $dupGroup -or $dupGroup.Count -eq 0) {
                Write-Host "  Fingerprint group (empty) for patient key $key, skipping."
                continue
            }

            if ($dupGroup.Count -eq 1) {
                # Only one tumor with this fingerprint; keep it
                foreach ($item in $dupGroup) {
                    if ($null -eq $item) { continue }
                    if ($null -eq $item.Index) {
                        Write-Warning "  Patient ${key}: single-entry dupGroup with null Index; skipping."
                        continue
                    }
                    $indicesToKeep[$item.Index] = $true
                }
            }
            else {
                # True duplicates: apply tiebreaker
                $winner = Apply-TiebreakerRules -DuplicateGroup $dupGroup -NsMgr $NsMgr

                if ($null -eq $winner) {
                    Write-Warning "  Patient ${key}: Apply-TiebreakerRules returned null; keeping all entries in this dupGroup."
                    foreach ($item in $dupGroup) {
                        if ($null -eq $item) { continue }
                        if ($null -eq $item.Index) {
                            Write-Warning "    dupGroup item with null Index; skipping."
                            continue
                        }
                        $indicesToKeep[$item.Index] = $true
                    }
                    continue
                }

                if ($null -eq $winner.Index) {
                    Write-Warning "  Patient ${key}: winner has null Index; keeping all entries in this dupGroup."
                    foreach ($item in $dupGroup) {
                        if ($null -eq $item) { continue }
                        if ($null -eq $item.Index) {
                            Write-Warning "    dupGroup item with null Index; skipping."
                            continue
                        }
                        $indicesToKeep[$item.Index] = $true
                    }
                    continue
                }

                $indicesToKeep[$winner.Index] = $true

                $allIndices     = ($dupGroup | ForEach-Object { $_.Index + 1 }) -join ","
                $removedIndices = ($dupGroup | Where-Object { $_.Index -ne $winner.Index } | ForEach-Object { $_.Index + 1 }) -join ","

				$dateLoaded   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportLoaded'
				$dateReceived = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
				$physician3   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'physician3'

				$reason =
					if (-not [string]::IsNullOrWhiteSpace($dateLoaded)) { "Earliest dateCaseReportLoaded" }
					elseif (-not [string]::IsNullOrWhiteSpace($dateReceived)) { "Earliest dateCaseReportReceived" }
					elseif (-not [string]::IsNullOrWhiteSpace($physician3)) { "Non-empty physician3" }
					else { "First occurrence" }

                $duplicateReport += [PSCustomObject]@{
                    PatientKey     = $key
                    AllIndices     = $allIndices
                    KeptIndex      = $winner.Index + 1
                    RemovedIndices = $removedIndices
                    Reason         = $reason
                    DateReceived   = $dateReceived
                    Physician3     = $physician3
                }
            }
        }
    }

    return @{
        IndicesToKeep = $indicesToKeep
        Report        = $duplicateReport
    }
}

function Get-DuplicatesByPrimaryKey {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    Write-Host "Grouping tumors by primary key (nameLast, nameFirst, dateOfBirth, primarySite, laterality)..."

    $primaryKeyGroups = @{}
    $duplicateReport  = @()
    $indicesToKeep    = @{}

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]

        # Get patient node
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        $nameLast     = ""
        $nameFirst    = ""
        $dateOfBirth  = ""
        $primarySite  = ""
        $laterality   = ""

        if ($patient -ne $null) {
            $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
            $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
            $dobNode = $patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $NsMgr)

            if ($nlNode) { $nameLast = $nlNode.InnerText }
            if ($nfNode) { $nameFirst = $nfNode.InnerText }
            if ($dobNode) { $dateOfBirth = $dobNode.InnerText }
        }

        # Tumor-level items
        $psNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='primarySite']", $NsMgr)
        if ($psNode) { $primarySite = $psNode.InnerText }

        $latNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='laterality']", $NsMgr)
        if ($latNode) { $laterality = $latNode.InnerText }

        # Build primary key (no normalization so the behavior is transparent)
        $key = "$nameLast|$nameFirst|$dateOfBirth|$primarySite|$laterality"

        if ([string]::IsNullOrWhiteSpace($key)) {
            # If everything is blank, just keep this tumor and move on
            $indicesToKeep[$i] = $true
            continue
        }

        if (-not $primaryKeyGroups.ContainsKey($key)) {
            $primaryKeyGroups[$key] = @()
        }

        $primaryKeyGroups[$key] += @{
            Index   = $i
            Tumor   = $tumor
            Patient = $patient
        }
    }

    foreach ($key in $primaryKeyGroups.Keys) {
        $group = $primaryKeyGroups[$key]

        if ($group.Count -eq 1) {
            # Only one tumor with this primary key; keep it
            $indicesToKeep[$group[0].Index] = $true
            continue
        }

        # Multiple tumors share this primary key - apply tiebreaker
        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $NsMgr

        if ($null -eq $winner -or $null -eq $winner.Index) {
            Write-Warning "PrimaryKey $key : Apply-TiebreakerRules returned null or invalid winner; keeping all entries."
            foreach ($item in $group) {
                if ($null -ne $item -and $null -ne $item.Index) {
                    $indicesToKeep[$item.Index] = $true
                }
            }
            continue
        }

        $indicesToKeep[$winner.Index] = $true

        $allIndices     = ($group | ForEach-Object { $_.Index + 1 }) -join ","
        $removedIndices = ($group | Where-Object { $_.Index -ne $winner.Index } | ForEach-Object { $_.Index + 1 }) -join ","

        $dateLoaded   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportLoaded'
        $dateReceived = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
        $physician3   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'physician3'

        $reason =
            if (-not [string]::IsNullOrWhiteSpace($dateLoaded)) { "Earliest dateCaseReportLoaded" }
            elseif (-not [string]::IsNullOrWhiteSpace($dateReceived)) { "Earliest dateCaseReportReceived" }
            elseif (-not [string]::IsNullOrWhiteSpace($physician3)) { "Non-empty physician3" }
            else { "First occurrence" }

        $duplicateReport += [PSCustomObject]@{
            PatientKey     = "PrimaryKey: $key"
            AllIndices     = $allIndices
            KeptIndex      = $winner.Index + 1
            RemovedIndices = $removedIndices
            Reason         = $reason
            DateReceived   = $dateReceived
            Physician3     = $physician3
        }
    }

    return @{
        IndicesToKeep = $indicesToKeep
        Report        = $duplicateReport
    }
}

function Get-DuplicatesByPathReport {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    Write-Host "Grouping tumors by pathReportNumber1..."
    $pathReportGroups = @{}
    $duplicateReport  = @()
    $indicesToKeep    = @{}

    # Group tumors by pathReportNumber1
    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $pathReportNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $NsMgr)
        
        $pathReportNumber1 = ""
        if ($pathReportNode) {
            $pathReportNumber1 = $pathReportNode.InnerText
        }
        
        # Skip tumors without pathReportNumber1
        if ([string]::IsNullOrWhiteSpace($pathReportNumber1)) {
            $indicesToKeep[$i] = $true
            continue
        }
        
        if (-not $pathReportGroups.ContainsKey($pathReportNumber1)) {
            $pathReportGroups[$pathReportNumber1] = @()
        }
        
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)
        $pathReportGroups[$pathReportNumber1] += @{
            Index = $i
            Tumor = $tumor
            Patient = $patient
        }
    }

    # Process groups with duplicates
    foreach ($pathReport in $pathReportGroups.Keys) {
        $group = $pathReportGroups[$pathReport]
        
        if ($group.Count -eq 1) {
            # No duplicates for this pathReportNumber1; keep it
            $indicesToKeep[$group[0].Index] = $true
            continue
        }
        
        # Multiple tumors with same pathReportNumber1 - apply tiebreaker
        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $NsMgr
        
        if ($null -eq $winner -or $null -eq $winner.Index) {
            Write-Warning "PathReport $pathReport : Apply-TiebreakerRules returned null or invalid winner; keeping all entries."
            foreach ($item in $group) {
                if ($null -ne $item -and $null -ne $item.Index) {
                    $indicesToKeep[$item.Index] = $true
                }
            }
            continue
        }
        
        $indicesToKeep[$winner.Index] = $true
        
        $allIndices     = ($group | ForEach-Object { $_.Index + 1 }) -join ","
        $removedIndices = ($group | Where-Object { $_.Index -ne $winner.Index } | ForEach-Object { $_.Index + 1 }) -join ","
        
        $dateLoaded   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportLoaded'
        $dateReceived = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'dateCaseReportReceived'
        $physician3   = Get-TiebreakerValue -Tumor $winner.Tumor -NsMgr $NsMgr -FieldId 'physician3'
        
        $reason =
            if (-not [string]::IsNullOrWhiteSpace($dateLoaded)) { "Earliest dateCaseReportLoaded" }
            elseif (-not [string]::IsNullOrWhiteSpace($dateReceived)) { "Earliest dateCaseReportReceived" }
            elseif (-not [string]::IsNullOrWhiteSpace($physician3)) { "Non-empty physician3" }
            else { "First occurrence" }
        
        $duplicateReport += [PSCustomObject]@{
            PatientKey     = "pathReportNumber1: $pathReport"
            AllIndices     = $allIndices
            KeptIndex      = $winner.Index + 1
            RemovedIndices = $removedIndices
            Reason         = $reason
            DateReceived   = $dateReceived
            Physician3     = $physician3
        }
    }

    return @{
        IndicesToKeep = $indicesToKeep
        Report        = $duplicateReport
    }
}

function Write-DedupedXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [hashtable]$IndicesToKeep,
        [string]$OutputPath
    )

    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    $declNode = $XmlDoc.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlDeclaration] } |
        Select-Object -First 1
    if ($declNode) {
        $newDecl = $newDoc.CreateXmlDeclaration($declNode.Version, $declNode.Encoding, $declNode.Standalone)
        [void]$newDoc.AppendChild($newDecl)
    }

    $root    = $XmlDoc.DocumentElement
    $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
    foreach ($attr in $root.Attributes) {
        $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
        $newAttr.Value = $attr.Value
        [void]$newRoot.Attributes.Append($newAttr)
    }
    [void]$newDoc.AppendChild($newRoot)

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

    # Proper namespace manager
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
    $nsMgr.AddNamespace("n", $root.NamespaceURI)

    foreach ($patientNode in $root.SelectNodes("./n:Patient", $nsMgr)) {
        $tumorsInPatient = $patientNode.SelectNodes("./n:Tumor", $nsMgr)

        $hasKeptTumor = $false
        foreach ($tumor in $tumorsInPatient) {
            if ($keptTumorNodes.ContainsKey($tumor)) {
                $hasKeptTumor = $true
                break
            }
        }

        if ($hasKeptTumor) {
            $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)

            foreach ($attr in $patientNode.Attributes) {
                $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
                $newAttr.Value = $attr.Value
                [void]$newPatient.Attributes.Append($newAttr)
            }

            foreach ($child in $patientNode.ChildNodes) {
                if ($child.LocalName -eq "Item") {
                    $imported = $newDoc.ImportNode($child, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }

            foreach ($tumor in $tumorsInPatient) {
                if ($keptTumorNodes.ContainsKey($tumor)) {
                    $imported = $newDoc.ImportNode($tumor, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }

            [void]$newRoot.AppendChild($newPatient)
        }
    }

    $settings                = New-Object System.Xml.XmlWriterSettings
    $settings.Indent         = $true
    $settings.NewLineChars   = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Show-DeduplicationPreview {
    param(
        [hashtable]$Result,
        [int]$OriginalCount,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$DedupType
    )

    $dedupedCount = $Result.IndicesToKeep.Count
    $removedCount = $OriginalCount - $dedupedCount
    $duplicateCount = $Result.Report.Count

    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Deduplication Preview - $DedupType"
    $previewForm.Width = 1400
    $previewForm.Height = 700
    $previewForm.StartPosition = "CenterScreen"
    $previewForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $previewForm.MaximizeBox = $false
    $previewForm.MinimizeBox = $false

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1360, 40)
    $lblSummary.Text = "Original tumors: $OriginalCount | Will keep: $dedupedCount | Will remove: $removedCount duplicates | Duplicate groups: $duplicateCount"
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
    $grid.AutoSizeColumnsMode = "AllCells"

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("PatientKey", [string])
    [void]$table.Columns.Add("AllIndices", [string])
    [void]$table.Columns.Add("KeptIndex", [string])
    [void]$table.Columns.Add("RemovedIndices", [string])
    [void]$table.Columns.Add("Reason", [string])
    [void]$table.Columns.Add("DateReceived", [string])
    [void]$table.Columns.Add("Physician3", [string])

    foreach ($item in $Result.Report) {
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
    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = "Proceed with Deduplication"
    $btnProceed.Width = 200
    $btnProceed.Location = New-Object System.Drawing.Point(10, 580)
    $btnProceed.Anchor = 'Bottom,Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Width = 100
    $btnCancel.Location = New-Object System.Drawing.Point(220, 580)
    $btnCancel.Anchor = 'Bottom,Left'

    # Set CancelButton so ESC key and X button work properly
    $previewForm.CancelButton = $btnCancel

    # Proceed button handler
    $btnProceed.Add_Click({
        $previewForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $previewForm.Close()
    })

    # Cancel button handler
    $btnCancel.Add_Click({
        $previewForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $previewForm.Close()
    })

    # Handle form closing (X button) to ensure DialogResult is set
    $previewForm.Add_FormClosing({
        param($sender, $e)
        if ($sender.DialogResult -eq [System.Windows.Forms.DialogResult]::None) {
            $sender.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
    })

    # Add controls to form
    $previewForm.Controls.AddRange(@($lblSummary, $grid, $btnProceed, $btnCancel))

    $dialogResult = $previewForm.ShowDialog()

    # Only proceed if user clicked OK
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        # Map DedupType to file suffix
        $suffix = switch ($DedupType) {
            "TrueMatches" { "-ddtr" }
            "PrimaryKey"  { "-ddpk" }
            "PathReport"  { "-ddpr" }
            default       { "-dedup" }
        }

        # User clicked proceed - show the full report
        Show-DeduplicationReport `
            -Report $Result.Report `
            -IndicesToKeep $Result.IndicesToKeep `
            -OriginalCount $OriginalCount `
            -OriginalFilePath $OriginalFilePath `
            -XmlDoc $XmlDoc `
            -Tumors $Tumors `
            -FileSuffix $suffix
    }
    # If Cancel or closed, just return (do nothing)
    # Explicitly return nothing to avoid any return value issues
    return
}

function Show-DeduplicationReport {
    param(
        [array]$Report,
        [hashtable]$IndicesToKeep,
        [int]$OriginalCount,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [string]$FileSuffix = "-dedup"
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
    $grid.AutoSizeColumnsMode = "AllCells"

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
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName$FileSuffix.xml")

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
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName$FileSuffix-report.csv")

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