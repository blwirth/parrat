# assign-unified.ps1
# Unified NAACCR XML assignment dialog - combines Primary Site/Laterality, Facility, and Patient ID

. "$PSScriptRoot\syntax-helpers.ps1"

function Get-UnifiedAssignments {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [hashtable]$Options
    )

    $report = @()
    $tumorAssignments = @{}
    $patientAssignments = @{}
    $processedPatients = @{}
    $pidCounter = 0

    # Load maps if site/laterality assignment is enabled
    $maps = $null
    if ($Options.AssignSite -or $Options.AssignLaterality) {
        $scriptDir = $PSScriptRoot
        $maps = Get-CachedMaps -ScriptDir $scriptDir
    }

    # Determine PID starting value
    $pidStartValue = $Options.PidStartingNumber
    if ($Options.PidMode -eq "ReplaceZeros") {
        $pidStartValue = 90000001
    }

    Write-Host "Processing $($Tumors.Count) tumors for unified assignment..." -ForegroundColor Cyan
    $processStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        # Get patient name for display
        $nameLast = ""
        $nameFirst = ""
        if ($null -ne $patient) {
            $nameLast = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameLast"
            $nameFirst = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameFirst"
        }
        $patientName = "$nameLast, $nameFirst".Trim(', ')

        # Initialize report entry
        $entry = [PSCustomObject]@{
            TumorIndex = $i + 1
            PatientName = $patientName
            CurrentSite = ""
            ProposedSite = ""
            CurrentLaterality = ""
            ProposedLaterality = ""
            CurrentFacility = ""
            ProposedFacility = ""
            CurrentPid = ""
            ProposedPid = ""
            SourceText = ""
            HasChanges = $false
        }

        # Get current values
        $currentSite = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "primarySite").Trim()
        $currentLat = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "laterality").Trim()
        $currentFacility = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "reportingFacility").Trim()

        $entry.CurrentSite = $currentSite
        $entry.CurrentLaterality = $currentLat
        $entry.CurrentFacility = $currentFacility

        # Initialize tumor assignment
        $tumorAssignment = @{}

        # --- Site/Laterality Assignment ---
        if ($Options.AssignSite -or $Options.AssignLaterality) {
            $hasSite = -not [string]::IsNullOrWhiteSpace($currentSite)
            $hasLat = -not [string]::IsNullOrWhiteSpace($currentLat)

            # Get text fields
            $textPath = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcPath"
            $textPe = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcPe"
            $textLab = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcLabTests"

            $textCombined = (($textPath + " " + $textPe)).Trim()
            if (-not $textCombined) {
                $textCombined = $textLab.Trim()
            }

            $proposedSite = ""
            $proposedLat = ""

            if ($textCombined) {
                $low = $textCombined.ToLower()

                # Assign primary site if needed
                $needsSite = $Options.AssignSite -and (-not $hasSite -or $Options.SiteOverride)
                if ($needsSite) {
                    # Histology-based overrides
                    if ($low -match '\b(invasive ductal carcinoma|metastatic mammary carcinoma|progesterone receptor|estrogen receptor|ductal carcinoma in-situ)\b') {
                        $proposedSite = "C509"
                    }
                    elseif ($low -match '\brenal cell carcinoma\b') {
                        $proposedSite = "C649"
                    }
                    elseif ($low -match '\b(prostatectomy|prostatic adenocarcinoma|gleason)\b') {
                        $proposedSite = "C619"
                    }
                    elseif ($low -match '\b(cll|plasma cell myeloma|small lymphocytic lymphoma|chronic lymphocytic leukemia)\b') {
                        $proposedSite = "C421"
                    }
                    elseif ($low -match '\b(follicular lymphoma|diffuse large b-cell lymphoma|dlbcl)\b') {
                        $proposedSite = "C779"
                    }
                    elseif ($low -match '\b(mlh1|pms2|msh2|msh6)\b') {
                        $proposedSite = "C189"
                    }
                    elseif ($low -match '\bbone marrow\b') {
                        $proposedSite = "C421"
                    }
                    elseif ($low -match '\bserous carcinoma\b') {
                        $proposedSite = "C579"
                    }
                    elseif ($low -like '*dako pd-l1 22c3*' -or $low -like '*non-small cell carcinoma*' -or $low -match '\bnsclc\b' -or
                            ($low -match '\begfr\b' -and $low -match 'pd-l1') -or
                            ($low -match '\begfr\b' -and $low -match '\balk\b') -or
                            ($low -match 'pd-l1' -and $low -match '\balk\b')) {
                        $proposedSite = "C349"
                    }
                    elseif ($low -match '\bbraf mutation analysis\b') {
                        $proposedSite = "C449"
                    }
                    else {
                        # Standard topography lookup
                        $hasMel = $low.Contains("melanoma")
                        if ($hasMel) {
                            $proposedSite = Get-BestCode $maps.MelTopoMap $low
                            if ($proposedSite -eq "") { $proposedSite = "C449" }
                        }
                        else {
                            $proposedSite = Get-BestCode $maps.TopoMap $low
                        }
                    }
                }

                # Determine which site to use for laterality check
                $siteToCheck = if ($proposedSite) { $proposedSite } elseif ($hasSite) { $currentSite } else { "" }

                # Assign laterality if needed
                $needsLat = $Options.AssignLaterality -and (-not $hasLat -or $Options.LateralityOverride)
                if ($needsLat -and $siteToCheck) {
                    if ($maps.LateralityCodes.ContainsKey($siteToCheck)) {
                        $detectedLat = Get-Laterality $low
                        if ($detectedLat) {
                            $proposedLat = $detectedLat
                        }
                        else {
                            $proposedLat = "9"
                        }
                    }
                    else {
                        $proposedLat = "0"
                    }
                }

                # Store source text snippet
                if ($proposedSite -or $proposedLat) {
                    $entry.SourceText = if ($textCombined.Length -gt 200) { $textCombined.Substring(0, 200) + "..." } else { $textCombined }
                }
            }

            if ($proposedSite) {
                $entry.ProposedSite = $proposedSite
                $tumorAssignment.PrimarySite = $proposedSite
                $entry.HasChanges = $true
            }

            if ($proposedLat) {
                $entry.ProposedLaterality = $proposedLat
                $tumorAssignment.Laterality = $proposedLat
                $entry.HasChanges = $true
            }
        }

        # --- Facility Assignment ---
        if ($Options.AssignFacility) {
            $needsFacility = $Options.FacilityOverride -or [string]::IsNullOrWhiteSpace($currentFacility) -or ($currentFacility -match '^0+$')

            if ($needsFacility) {
                $entry.ProposedFacility = $Options.FacilityNumber
                $tumorAssignment.ReportingFacility = $Options.FacilityNumber
                $entry.HasChanges = $true
            }
        }

        # --- Patient ID Assignment ---
        if ($Options.AssignPid -and $null -ne $patient -and -not $processedPatients.ContainsKey($patient)) {
            $processedPatients[$patient] = $true

            $currentPid = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "patientIdNumber"
            $entry.CurrentPid = if ([string]::IsNullOrWhiteSpace($currentPid)) { "(none)" } else { $currentPid }

            $hasPid = -not [string]::IsNullOrWhiteSpace($currentPid)
            $shouldAssignPid = $false
            $pidValue = ""

            if ($Options.PidMode -eq "OverwriteAll") {
                $shouldAssignPid = $true
                $pidCounter++
                $pidValue = ($pidStartValue + $pidCounter - 1).ToString("D8")
            }
            elseif ($Options.PidMode -eq "ReplaceZeros") {
                if (-not $hasPid -or $currentPid -match '^0+$') {
                    $shouldAssignPid = $true
                    $pidCounter++
                    $pidValue = ($pidStartValue + $pidCounter - 1).ToString("D8")
                }
            }
            else {
                # Default mode: only assign if patient doesn't have an ID
                if (-not $hasPid) {
                    $shouldAssignPid = $true
                    $pidCounter++
                    $pidValue = ($pidStartValue + $pidCounter - 1).ToString("D8")
                }
            }

            if ($shouldAssignPid) {
                $entry.ProposedPid = $pidValue
                $patientAssignments[$patient] = $pidValue
                $entry.HasChanges = $true
            }
        }
        elseif ($Options.AssignPid -and $null -ne $patient -and $processedPatients.ContainsKey($patient)) {
            # Patient already processed - get current PID for display
            $currentPid = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "patientIdNumber"
            $entry.CurrentPid = if ([string]::IsNullOrWhiteSpace($currentPid)) { "(none)" } else { $currentPid }

            # If this patient has a pending assignment, show it
            if ($patientAssignments.ContainsKey($patient)) {
                $entry.ProposedPid = $patientAssignments[$patient]
            }
        }

        # Store tumor assignment if any changes
        if ($tumorAssignment.Count -gt 0) {
            $tumorAssignments[$i] = $tumorAssignment
        }

        $report += $entry
    }

    $processStopwatch.Stop()
    Write-Host ("Processed {0} tumors in {1:F2} seconds." -f $Tumors.Count, $processStopwatch.Elapsed.TotalSeconds) -ForegroundColor Cyan

    return @{
        Report = $report
        TumorAssignments = $tumorAssignments
        PatientAssignments = $patientAssignments
        Options = $Options
    }
}

function Write-UnifiedAssignedXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [hashtable]$TumorAssignments,
        [hashtable]$PatientAssignments,
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

    # Process each Patient
    foreach ($patientNode in $root.SelectNodes("./n:Patient", $NsMgr)) {
        $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)

        # Copy patient attributes
        foreach ($attr in $patientNode.Attributes) {
            $newAttr = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
            $newAttr.Value = $attr.Value
            [void]$newPatient.Attributes.Append($newAttr)
        }

        # Check if this patient needs a patientIdNumber
        $needsPid = $PatientAssignments.ContainsKey($patientNode)
        $patientIdValue = if ($needsPid) { $PatientAssignments[$patientNode] } else { $null }

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
                    if ($needsPid) {
                        $imported = $newDoc.ImportNode($child, $true)
                        $imported.InnerText = $patientIdValue
                        [void]$newPatient.AppendChild($imported)
                        $patientIdAdded = $true
                    }
                    else {
                        # Keep existing as-is
                        $imported = $newDoc.ImportNode($child, $true)
                        [void]$newPatient.AppendChild($imported)
                        $patientIdAdded = $true
                    }
                }
                else {
                    # Regular Item - add it
                    $imported = $newDoc.ImportNode($child, $true)
                    [void]$newPatient.AppendChild($imported)
                }
            }
            elseif ($child.LocalName -eq "Tumor") {
                # Before adding the first tumor, add patientIdNumber if needed and not already added
                if ($child -eq $firstTumor -and $needsPid -and -not $patientIdAdded) {
                    $item = $newDoc.CreateElement("Item", $root.NamespaceURI)
                    $item.SetAttribute("naaccrId", "patientIdNumber")
                    $item.SetAttribute("naaccrNum", "20")
                    $item.InnerText = $patientIdValue
                    [void]$newPatient.AppendChild($item)
                    $patientIdAdded = $true
                }

                # Find this tumor's index in the global list
                $tumorIndex = -1
                for ($i = 0; $i -lt $Tumors.Count; $i++) {
                    if ($Tumors[$i] -eq $child) {
                        $tumorIndex = $i
                        break
                    }
                }

                # Clone the tumor
                $newTumor = $newDoc.ImportNode($child, $true)

                # Apply tumor assignments if this tumor has them
                if ($tumorIndex -ge 0 -and $TumorAssignments.ContainsKey($tumorIndex)) {
                    $assignment = $TumorAssignments[$tumorIndex]

                    # Set primary site if proposed
                    if ($assignment.PrimarySite) {
                        $siteNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='primarySite']", $NsMgr)
                        if ($siteNode) {
                            $siteNode.InnerText = $assignment.PrimarySite
                        }
                        else {
                            $siteNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                            $attr = $newDoc.CreateAttribute("naaccrId")
                            $attr.Value = "primarySite"
                            [void]$siteNode.Attributes.Append($attr)
                            $siteNode.InnerText = $assignment.PrimarySite
                            [void]$newTumor.AppendChild($siteNode)
                        }
                    }

                    # Set laterality if proposed
                    if ($assignment.Laterality) {
                        $latNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='laterality']", $NsMgr)
                        if ($latNode) {
                            $latNode.InnerText = $assignment.Laterality
                        }
                        else {
                            $latNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                            $attr = $newDoc.CreateAttribute("naaccrId")
                            $attr.Value = "laterality"
                            [void]$latNode.Attributes.Append($attr)
                            $latNode.InnerText = $assignment.Laterality
                            [void]$newTumor.AppendChild($latNode)
                        }
                    }

                    # Set reportingFacility if proposed
                    if ($assignment.ReportingFacility) {
                        $facNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", $NsMgr)
                        if ($facNode) {
                            $facNode.InnerText = $assignment.ReportingFacility
                        }
                        else {
                            $facNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                            $attr = $newDoc.CreateAttribute("naaccrId")
                            $attr.Value = "reportingFacility"
                            [void]$facNode.Attributes.Append($attr)
                            $facNode.InnerText = $assignment.ReportingFacility
                            [void]$newTumor.AppendChild($facNode)
                        }
                    }
                }

                [void]$newPatient.AppendChild($newTumor)
            }
        }

        # If patient has no tumors and needs ID, add it at the end
        if ($needsPid -and -not $patientIdAdded) {
            $item = $newDoc.CreateElement("Item", $root.NamespaceURI)
            $item.SetAttribute("naaccrId", "patientIdNumber")
            $item.SetAttribute("naaccrNum", "20")
            $item.InnerText = $patientIdValue
            [void]$newPatient.AppendChild($item)
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
}

function Get-FileSuffix {
    param([hashtable]$Options, [array]$Report)

    $suffixParts = @()

    # Check if each option produced any changes
    $hasSiteChanges = $null -ne ($Report | Where-Object { $_.ProposedSite })
    $hasLatChanges = $null -ne ($Report | Where-Object { $_.ProposedLaterality })
    $hasFacChanges = $null -ne ($Report | Where-Object { $_.ProposedFacility })
    $hasPidChanges = $null -ne ($Report | Where-Object { $_.ProposedPid })

    if ($Options.AssignSite -and $hasSiteChanges) { $suffixParts += "psite" }
    if ($Options.AssignLaterality -and $hasLatChanges) { $suffixParts += "lat" }
    if ($Options.AssignFacility -and $hasFacChanges) { $suffixParts += "fac" }
    if ($Options.AssignPid -and $hasPidChanges) { $suffixParts += "pid" }

    if ($suffixParts.Count -eq 0) { return "assigned" }
    return $suffixParts -join "-"
}

