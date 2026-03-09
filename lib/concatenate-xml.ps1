# concatenate-xml.ps1
# NAACCR XML concatenation utilities

. "$PSScriptRoot\syntax-helpers.ps1"

function Get-DuplicatePatientIds {
    param(
        [array]$HeaderInfos
    )

    $patientIdCounts = @{}

    foreach ($item in $HeaderInfos) {
        $xmlDoc = $item.Info.XmlDoc
        $nsMgr = $item.Info.NsMgr
        $root = $xmlDoc.DocumentElement

        $patients = $root.SelectNodes("./n:Patient", $nsMgr)
        foreach ($patient in $patients) {
            $pidNode = $patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $nsMgr)
            if ($pidNode -and -not [string]::IsNullOrWhiteSpace($pidNode.InnerText)) {
                $patientIdValue = $pidNode.InnerText.Trim()
                if ($patientIdCounts.ContainsKey($patientIdValue)) {
                    $patientIdCounts[$patientIdValue]++
                } else {
                    $patientIdCounts[$patientIdValue] = 1
                }
            }
        }
    }

    # Return only duplicates (count > 1)
    $duplicates = @{}
    foreach ($key in $patientIdCounts.Keys) {
        if ($patientIdCounts[$key] -gt 1) {
            $duplicates[$key] = $patientIdCounts[$key]
        }
    }

    return $duplicates
}

function Get-XmlHeaderInfo {
    param(
        [string]$FilePath
    )

    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($FilePath)

        # Get XML declaration version
        $declNode = $xml.ChildNodes | Where-Object { $_ -is [System.Xml.XmlDeclaration] } | Select-Object -First 1
        $xmlVersion = if ($declNode) { $declNode.Version } else { "1.0" }

        # Get NaaccrData attributes
        $root = $xml.DocumentElement
        if ($null -eq $root -or $root.LocalName -ne "NaaccrData") {
            throw "Root element is not NaaccrData"
        }

        $baseDictionaryUri = $root.GetAttribute("baseDictionaryUri")
        $xmlns = $root.NamespaceURI
        $recordType = $root.GetAttribute("recordType")

        # Get tumor count
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("n", $xmlns)
        $tumors = $xml.SelectNodes("//n:Tumor", $nsMgr)
        $tumorCount = $tumors.Count

        return @{
            XmlVersion = $xmlVersion
            BaseDictionaryUri = $baseDictionaryUri
            Xmlns = $xmlns
            RecordType = $recordType
            TumorCount = $tumorCount
            XmlDoc = $xml
            NsMgr = $nsMgr
            Tumors = $tumors
            Success = $true
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-XmlHeaders {
    param(
        [array]$XmlFiles
    )

    if ($XmlFiles.Count -eq 0) {
        return @{ Success = $false; Error = "No files provided" }
    }

    $headerInfos = @()
    $errors = @()

    # Load and validate each file
    foreach ($file in $XmlFiles) {
        $info = Get-XmlHeaderInfo -FilePath $file
        if (-not $info.Success) {
            $errors += "Error loading $file : $($info.Error)"
            continue
        }

        $headerInfos += @{
            FilePath = $file
            Info = $info
        }
    }

    if ($errors.Count -gt 0) {
        return @{
            Success = $false
            Error = ($errors -join "`n")
        }
    }

    if ($headerInfos.Count -eq 0) {
        return @{ Success = $false; Error = "No valid XML files found" }
    }

    # Check if all headers match
    $first = $headerInfos[0].Info

    foreach ($item in $headerInfos) {
        $info = $item.Info

        if ($info.XmlVersion -ne $first.XmlVersion) {
            return @{
                Success = $false
                Error = "XML version mismatch. File '$($item.FilePath)' has version '$($info.XmlVersion)' but expected '$($first.XmlVersion)'"
            }
        }

        if ($info.BaseDictionaryUri -ne $first.BaseDictionaryUri) {
            return @{
                Success = $false
                Error = "baseDictionaryUri mismatch. File '$($item.FilePath)' has '$($info.BaseDictionaryUri)' but expected '$($first.BaseDictionaryUri)'"
            }
        }

        if ($info.Xmlns -ne $first.Xmlns) {
            return @{
                Success = $false
                Error = "xmlns mismatch. File '$($item.FilePath)' has '$($info.Xmlns)' but expected '$($first.Xmlns)'"
            }
        }

        if ($info.RecordType -ne $first.RecordType) {
            return @{
                Success = $false
                Error = "recordType mismatch. File '$($item.FilePath)' has '$($info.RecordType)' but expected '$($first.RecordType)'"
            }
        }
    }

    return @{
        Success = $true
        HeaderInfos = $headerInfos
        ReferenceInfo = $first
    }
}

function Test-XmlHeaderAgainstReference {
    param(
        [hashtable]$NewInfo,
        [hashtable]$ReferenceInfo
    )

    $errors = @()

    if ($NewInfo.XmlVersion -ne $ReferenceInfo.XmlVersion) {
        $errors += "XML version mismatch: '$($NewInfo.XmlVersion)' vs expected '$($ReferenceInfo.XmlVersion)'"
    }

    if ($NewInfo.BaseDictionaryUri -ne $ReferenceInfo.BaseDictionaryUri) {
        $errors += "baseDictionaryUri mismatch: '$($NewInfo.BaseDictionaryUri)' vs expected '$($ReferenceInfo.BaseDictionaryUri)'"
    }

    if ($NewInfo.Xmlns -ne $ReferenceInfo.Xmlns) {
        $errors += "xmlns mismatch: '$($NewInfo.Xmlns)' vs expected '$($ReferenceInfo.Xmlns)'"
    }

    if ($NewInfo.RecordType -ne $ReferenceInfo.RecordType) {
        $errors += "recordType mismatch: '$($NewInfo.RecordType)' vs expected '$($ReferenceInfo.RecordType)'"
    }

    if ($errors.Count -gt 0) {
        return @{
            Success = $false
            Error = ($errors -join "`n")
        }
    }

    return @{ Success = $true }
}

function Get-TumorPreview {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [int]$MaxTumors = 100
    )

    $preview = @()
    $count = [Math]::Min($Tumors.Count, $MaxTumors)

    for ($i = 0; $i -lt $count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        $nameLast = ""
        $nameFirst = ""
        $dateOfDiagnosis = ""
        $pathReportNumber1 = ""

        if ($null -ne $patient) {
            $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
            $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)

            if ($nlNode) { $nameLast = $nlNode.InnerText }
            if ($nfNode) { $nameFirst = $nfNode.InnerText }
        }

        $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $NsMgr)
        if ($dxNode) { $dateOfDiagnosis = $dxNode.InnerText }

        $pathNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $NsMgr)
        if ($pathNode) { $pathReportNumber1 = $pathNode.InnerText }

        $preview += [PSCustomObject]@{
            TumorIndex = $i + 1
            NameLast = $nameLast
            NameFirst = $nameFirst
            DateOfDiagnosis = $dateOfDiagnosis
            PathReportNumber1 = $pathReportNumber1
        }
    }

    return $preview
}

function Write-ConcatenatedXml {
    param(
        [array]$HeaderInfos,
        [hashtable]$ReferenceInfo,
        [string]$OutputPath,
        [switch]$ShowProgress,
        [switch]$ReassignPatientIds
    )

    # Create new XML document
    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Add XML declaration
    $newDecl = $newDoc.CreateXmlDeclaration($ReferenceInfo.XmlVersion, "UTF-8", $null)
    [void]$newDoc.AppendChild($newDecl)

    # Create NaaccrData root element
    $newRoot = $newDoc.CreateElement("NaaccrData", $ReferenceInfo.Xmlns)
    $newRoot.SetAttribute("baseDictionaryUri", $ReferenceInfo.BaseDictionaryUri)
    $newRoot.SetAttribute("recordType", $ReferenceInfo.RecordType)
    $newRoot.SetAttribute("timeGenerated", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"))
    $newRoot.SetAttribute("specificationVersion", "1.7")
    [void]$newDoc.AppendChild($newRoot)

    $totalFiles = $HeaderInfos.Count
    $currentFile = 0

    # Concatenate all Patient elements from all files
    foreach ($item in $HeaderInfos) {
        $currentFile++

        if ($ShowProgress -and ($currentFile % 50 -eq 0 -or $currentFile -eq $totalFiles)) {
            Write-Progress -Activity "Concatenating XML files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
        }

        $xmlDoc = $item.Info.XmlDoc
        $nsMgr = $item.Info.NsMgr
        $root = $xmlDoc.DocumentElement

        # Get all Patient nodes from this file
        $patients = $root.SelectNodes("./n:Patient", $nsMgr)

        foreach ($patient in $patients) {
            # Import the patient node (deep copy)
            $importedPatient = $newDoc.ImportNode($patient, $true)
            [void]$newRoot.AppendChild($importedPatient)
        }
    }

    # Reassign patient IDs if requested
    if ($ReassignPatientIds) {
        $xmlns = $ReferenceInfo.Xmlns
        $newNsMgr = New-Object System.Xml.XmlNamespaceManager($newDoc.NameTable)
        $newNsMgr.AddNamespace("n", $xmlns)

        $allPatients = $newRoot.SelectNodes("./n:Patient", $newNsMgr)
        $patientId = 1

        foreach ($patient in $allPatients) {
            # Find existing patientIdNumber Item
            $pidNode = $patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $newNsMgr)

            if ($pidNode) {
                # Update existing node
                $pidNode.InnerText = $patientId.ToString().PadLeft(8, '0')
            }
            else {
                # Create new patientIdNumber Item as first child
                $newItem = $newDoc.CreateElement("Item", $xmlns)
                $newItem.SetAttribute("naaccrId", "patientIdNumber")
                $newItem.InnerText = $patientId.ToString().PadLeft(8, '0')

                if ($patient.HasChildNodes) {
                    [void]$patient.InsertBefore($newItem, $patient.FirstChild)
                }
                else {
                    [void]$patient.AppendChild($newItem)
                }
            }

            $patientId++
        }
    }

    if ($ShowProgress) {
        Write-Progress -Activity "Concatenating XML files" -Status "Writing output file..." -PercentComplete 95
    }

    # Save with formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()

    if ($ShowProgress) {
        Write-Progress -Activity "Concatenating XML files" -Completed
    }
}

function Write-ConcatenatedXmlFromPaths {
    param(
        [string[]]$FilePaths,
        [string]$OutputPath
    )

    # Fast streaming mode for large batches - validates headers on first file only
    # then streams Patient nodes from each file

    $totalFiles = $FilePaths.Count
    $currentFile = 0
    $totalTumors = 0

    Write-Progress -Activity "Concatenating XML files" -Status "Reading first file for header info..." -PercentComplete 0

    # Get reference info from first file
    $firstFile = $FilePaths[0]
    $refInfo = Get-XmlHeaderInfo -FilePath $firstFile
    if (-not $refInfo.Success) {
        return @{
            Success = $false
            Error = "Failed to read first file: $($refInfo.Error)"
        }
    }

    # Create new XML document
    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Add XML declaration
    $newDecl = $newDoc.CreateXmlDeclaration($refInfo.XmlVersion, "UTF-8", $null)
    [void]$newDoc.AppendChild($newDecl)

    # Create NaaccrData root element
    $newRoot = $newDoc.CreateElement("NaaccrData", $refInfo.Xmlns)
    $newRoot.SetAttribute("baseDictionaryUri", $refInfo.BaseDictionaryUri)
    $newRoot.SetAttribute("recordType", $refInfo.RecordType)
    $newRoot.SetAttribute("timeGenerated", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"))
    $newRoot.SetAttribute("specificationVersion", "1.7")
    [void]$newDoc.AppendChild($newRoot)

    $errors = @()

    foreach ($filePath in $FilePaths) {
        $currentFile++

        if ($currentFile % 50 -eq 0 -or $currentFile -eq $totalFiles) {
            Write-Progress -Activity "Concatenating XML files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 90)
        }

        try {
            # Load XML file
            $xml = New-Object System.Xml.XmlDocument
            $xml.XmlResolver = $null
            $xml.Load($filePath)

            $root = $xml.DocumentElement
            if ($null -eq $root -or $root.LocalName -ne "NaaccrData") {
                $errors += "Skipped '$([System.IO.Path]::GetFileName($filePath))': Not a valid NAACCR XML"
                continue
            }

            # Quick header validation (skip detailed validation for speed)
            $fileRecordType = $root.GetAttribute("recordType")
            if ($fileRecordType -ne $refInfo.RecordType) {
                $errors += "Skipped '$([System.IO.Path]::GetFileName($filePath))': recordType mismatch ($fileRecordType vs $($refInfo.RecordType))"
                continue
            }

            # Set up namespace manager
            $xmlns = $root.NamespaceURI
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
            $nsMgr.AddNamespace("n", $xmlns)

            # Get all Patient nodes from this file
            $patients = $root.SelectNodes("./n:Patient", $nsMgr)

            foreach ($patient in $patients) {
                $importedPatient = $newDoc.ImportNode($patient, $true)
                [void]$newRoot.AppendChild($importedPatient)

                # Count tumors
                $tumors = $patient.SelectNodes("./n:Tumor", $nsMgr)
                $totalTumors += $tumors.Count
            }
        }
        catch {
            $errors += "Error processing '$([System.IO.Path]::GetFileName($filePath))': $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Concatenating XML files" -Status "Writing output file..." -PercentComplete 95

    # Save with formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()

    Write-Progress -Activity "Concatenating XML files" -Completed

    return @{
        Success = $true
        FilesProcessed = $currentFile
        TotalTumors = $totalTumors
        Errors = $errors
        OutputPath = $OutputPath
    }
}
