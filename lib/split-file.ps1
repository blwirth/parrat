# split-file.ps1
# Split NAACCR XML or HL7 files alphabetically by patient last name

function Get-AlphabetRanges {
    <#
    .SYNOPSIS
    Returns alphabet ranges for the given split count

    .PARAMETER SplitCount
    Number of files to split into (2-5)

    .OUTPUTS
    Array of hashtables with StartLetter, EndLetter, Label properties
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(2, 5)]
        [int]$SplitCount
    )

    switch ($SplitCount) {
        2 {
            return @(
                @{ StartLetter = 'A'; EndLetter = 'M'; Label = 'A-M' },
                @{ StartLetter = 'N'; EndLetter = 'Z'; Label = 'N-Z' }
            )
        }
        3 {
            return @(
                @{ StartLetter = 'A'; EndLetter = 'I'; Label = 'A-I' },
                @{ StartLetter = 'J'; EndLetter = 'R'; Label = 'J-R' },
                @{ StartLetter = 'S'; EndLetter = 'Z'; Label = 'S-Z' }
            )
        }
        4 {
            return @(
                @{ StartLetter = 'A'; EndLetter = 'F'; Label = 'A-F' },
                @{ StartLetter = 'G'; EndLetter = 'L'; Label = 'G-L' },
                @{ StartLetter = 'M'; EndLetter = 'R'; Label = 'M-R' },
                @{ StartLetter = 'S'; EndLetter = 'Z'; Label = 'S-Z' }
            )
        }
        5 {
            return @(
                @{ StartLetter = 'A'; EndLetter = 'E'; Label = 'A-E' },
                @{ StartLetter = 'F'; EndLetter = 'J'; Label = 'F-J' },
                @{ StartLetter = 'K'; EndLetter = 'O'; Label = 'K-O' },
                @{ StartLetter = 'P'; EndLetter = 'T'; Label = 'P-T' },
                @{ StartLetter = 'U'; EndLetter = 'Z'; Label = 'U-Z' }
            )
        }
    }
}

function Get-FileSplitBucket {
    <#
    .SYNOPSIS
    Determines which bucket (0 to n-1) a last name falls into

    .PARAMETER LastName
    The patient's last name

    .PARAMETER SplitCount
    Number of files to split into (2-5)

    .OUTPUTS
    Integer bucket index (0 to SplitCount-1). Malformed names go to last bucket.
    #>
    param(
        [string]$LastName,
        [Parameter(Mandatory=$true)]
        [ValidateRange(2, 5)]
        [int]$SplitCount
    )

    # Handle empty/null last names - go to last bucket
    if ([string]::IsNullOrWhiteSpace($LastName)) {
        return $SplitCount - 1
    }

    # Trim and check again (in case string had only whitespace)
    $trimmed = $LastName.Trim()
    if ([string]::IsNullOrEmpty($trimmed)) {
        return $SplitCount - 1
    }

    # Get first character and normalize to uppercase
    $firstChar = $trimmed.Substring(0, 1).ToUpperInvariant()

    # Check if it's a letter A-Z
    if ($firstChar -lt 'A' -or $firstChar -gt 'Z') {
        # Non-alphabetic - go to last bucket
        return $SplitCount - 1
    }

    $ranges = Get-AlphabetRanges -SplitCount $SplitCount

    for ($i = 0; $i -lt $ranges.Count; $i++) {
        $range = $ranges[$i]
        if ($firstChar -ge $range.StartLetter -and $firstChar -le $range.EndLetter) {
            return $i
        }
    }

    # Fallback to last bucket
    return $SplitCount - 1
}

function Get-XmlFileSplitInfo {
    <#
    .SYNOPSIS
    Quick scan XML file to count patients/tumors and extract last names

    .PARAMETER FilePath
    Path to the NAACCR XML file

    .OUTPUTS
    Hashtable with TotalRecords, LastNames array, XmlInfo (header info), Success, Error
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        # Load XML document
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($FilePath)

        # Get namespace
        $root = $xml.DocumentElement
        if ($null -eq $root -or $root.LocalName -ne "NaaccrData") {
            return @{
                Success = $false
                Error = "Not a valid NAACCR XML file (root element is not NaaccrData)"
            }
        }

        $xmlns = $root.NamespaceURI
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("n", $xmlns)

        # Get header info for later use when writing
        $declNode = $xml.ChildNodes | Where-Object { $_ -is [System.Xml.XmlDeclaration] } | Select-Object -First 1
        $xmlVersion = if ($declNode) { $declNode.Version } else { "1.0" }

        $xmlInfo = @{
            XmlVersion = $xmlVersion
            Xmlns = $xmlns
            BaseDictionaryUri = $root.GetAttribute("baseDictionaryUri")
            RecordType = $root.GetAttribute("recordType")
            SpecificationVersion = $root.GetAttribute("specificationVersion")
        }

        # Get all Patient nodes
        $patients = $xml.SelectNodes("//n:Patient", $nsMgr)

        # Extract last names for each patient
        $patientData = New-Object System.Collections.ArrayList
        $totalTumors = 0

        foreach ($patient in $patients) {
            $nameLastNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $nsMgr)
            $nameLast = if ($nameLastNode) { $nameLastNode.InnerText } else { "" }

            # Count tumors in this patient
            $tumors = $patient.SelectNodes("./n:Tumor", $nsMgr)
            $tumorCount = if ($tumors) { $tumors.Count } else { 0 }
            $totalTumors += $tumorCount

            [void]$patientData.Add(@{
                LastName = $nameLast
                TumorCount = $tumorCount
                PatientNode = $patient
            })
        }

        return @{
            Success = $true
            TotalPatients = $patients.Count
            TotalTumors = $totalTumors
            PatientData = $patientData
            XmlInfo = $xmlInfo
            XmlDoc = $xml
            NsMgr = $nsMgr
        }
    }
    catch {
        return @{
            Success = $false
            Error = "Error scanning XML file: $($_.Exception.Message)"
        }
    }
}

function Get-Hl7FileSplitInfo {
    <#
    .SYNOPSIS
    Quick scan HL7 file to count messages and extract last names

    .PARAMETER FilePath
    Path to the HL7 file

    .OUTPUTS
    Hashtable with TotalRecords, MessageData array, Success, Error
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding ASCII

        if ([string]::IsNullOrWhiteSpace($content)) {
            return @{
                Success = $false
                Error = "File is empty"
            }
        }

        # Normalize line endings
        $content = $content -replace "`r`n", "`n"
        $content = $content -replace "`r", "`n"

        # Split into messages by MSH|
        $messageData = New-Object System.Collections.ArrayList
        $currentMessageLines = New-Object System.Collections.ArrayList

        $allLines = $content -split "`n"

        foreach ($line in $allLines) {
            $trimmedLine = $line.Trim()
            if ([string]::IsNullOrEmpty($trimmedLine)) { continue }

            if ($trimmedLine.StartsWith("MSH|")) {
                # Start of new message - save previous if exists
                if ($currentMessageLines.Count -gt 0) {
                    $msgText = $currentMessageLines -join "`n"
                    $lastName = Get-Hl7LastName -MessageText $msgText
                    [void]$messageData.Add(@{
                        LastName = $lastName
                        MessageText = $msgText
                    })
                    $currentMessageLines.Clear()
                }
                [void]$currentMessageLines.Add($trimmedLine)
            }
            else {
                if ($currentMessageLines.Count -gt 0) {
                    [void]$currentMessageLines.Add($trimmedLine)
                }
            }
        }

        # Don't forget the last message
        if ($currentMessageLines.Count -gt 0) {
            $msgText = $currentMessageLines -join "`n"
            $lastName = Get-Hl7LastName -MessageText $msgText
            [void]$messageData.Add(@{
                LastName = $lastName
                MessageText = $msgText
            })
        }

        return @{
            Success = $true
            TotalMessages = $messageData.Count
            MessageData = $messageData
        }
    }
    catch {
        return @{
            Success = $false
            Error = "Error scanning HL7 file: $($_.Exception.Message)"
        }
    }
}

function Get-Hl7LastName {
    <#
    .SYNOPSIS
    Extract last name from an HL7 message text
    #>
    param(
        [string]$MessageText
    )

    if ([string]::IsNullOrWhiteSpace($MessageText)) {
        return ""
    }

    $lines = $MessageText -split "`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("PID|")) {
            # PID-5 is patient name (field index 5 after split by |)
            $fields = $trimmed -split '\|'
            if ($fields.Count -gt 5) {
                $nameField = $fields[5]
                # Name format: last^first^middle
                $components = $nameField -split '\^'
                if ($components.Count -gt 0) {
                    return $components[0]
                }
            }
            break
        }
    }

    return ""
}

function Get-SplitDistribution {
    <#
    .SYNOPSIS
    Calculate how records will be distributed across buckets

    .PARAMETER LastNames
    Array of last names

    .PARAMETER SplitCount
    Number of files to split into

    .OUTPUTS
    Array of counts per bucket
    #>
    param(
        [array]$LastNames,
        [int]$SplitCount
    )

    $buckets = @(0) * $SplitCount

    foreach ($name in $LastNames) {
        $bucket = Get-FileSplitBucket -LastName $name -SplitCount $SplitCount
        $buckets[$bucket]++
    }

    return $buckets
}

function Split-XmlFile {
    <#
    .SYNOPSIS
    Split an NAACCR XML file into multiple files by last name

    .PARAMETER ScanResult
    Result from Get-XmlFileSplitInfo

    .PARAMETER FilePath
    Original file path

    .PARAMETER SplitCount
    Number of files to split into

    .PARAMETER OutputDirectory
    Directory to write output files

    .OUTPUTS
    Hashtable with Success, OutputFiles array, Error
    #>
    param(
        [Parameter(Mandatory=$true)][hashtable]$ScanResult,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][int]$SplitCount,
        [Parameter(Mandatory=$true)][string]$OutputDirectory
    )

    try {
        $ranges = Get-AlphabetRanges -SplitCount $SplitCount
        $xmlInfo = $ScanResult.XmlInfo

        # Get base filename without extension
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $extension = [System.IO.Path]::GetExtension($FilePath)

        # Create output documents for each bucket
        $outputDocs = @()
        $outputPaths = @()

        for ($i = 0; $i -lt $SplitCount; $i++) {
            $range = $ranges[$i]
            $outputFileName = "{0}_{1}{2}" -f $baseName, $range.Label, $extension
            $outputPath = [System.IO.Path]::Combine($OutputDirectory, $outputFileName)
            $outputPaths += $outputPath

            # Create new XML document
            $newDoc = New-Object System.Xml.XmlDocument
            $newDoc.XmlResolver = $null

            # Add XML declaration
            $decl = $newDoc.CreateXmlDeclaration($xmlInfo.XmlVersion, "UTF-8", $null)
            [void]$newDoc.AppendChild($decl)

            # Create NaaccrData root element
            $newRoot = $newDoc.CreateElement("NaaccrData", $xmlInfo.Xmlns)
            $newRoot.SetAttribute("baseDictionaryUri", $xmlInfo.BaseDictionaryUri)
            $newRoot.SetAttribute("recordType", $xmlInfo.RecordType)
            $newRoot.SetAttribute("timeGenerated", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"))
            if (-not [string]::IsNullOrEmpty($xmlInfo.SpecificationVersion)) {
                $newRoot.SetAttribute("specificationVersion", $xmlInfo.SpecificationVersion)
            }
            [void]$newDoc.AppendChild($newRoot)

            $outputDocs += @{
                Doc = $newDoc
                Root = $newRoot
                Path = $outputPath
                PatientCount = 0
                TumorCount = 0
            }
        }

        # Distribute patients to appropriate buckets
        foreach ($patientData in $ScanResult.PatientData) {
            $bucket = Get-FileSplitBucket -LastName $patientData.LastName -SplitCount $SplitCount
            $targetDoc = $outputDocs[$bucket]

            # Import patient node
            $importedPatient = $targetDoc.Doc.ImportNode($patientData.PatientNode, $true)
            [void]$targetDoc.Root.AppendChild($importedPatient)

            $targetDoc.PatientCount++
            $targetDoc.TumorCount += $patientData.TumorCount
        }

        # Write output files
        $outputFiles = @()

        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.NewLineChars = "`r`n"
        $settings.NewLineHandling = "Replace"
        $settings.Encoding = [System.Text.Encoding]::UTF8

        foreach ($outputDoc in $outputDocs) {
            $writer = [System.Xml.XmlWriter]::Create($outputDoc.Path, $settings)
            $outputDoc.Doc.Save($writer)
            $writer.Close()

            $outputFiles += @{
                Path = $outputDoc.Path
                PatientCount = $outputDoc.PatientCount
                TumorCount = $outputDoc.TumorCount
            }
        }

        return @{
            Success = $true
            OutputFiles = $outputFiles
        }
    }
    catch {
        return @{
            Success = $false
            Error = "Error splitting XML file: $($_.Exception.Message)"
        }
    }
}

function Split-Hl7File {
    <#
    .SYNOPSIS
    Split an HL7 file into multiple files by last name

    .PARAMETER ScanResult
    Result from Get-Hl7FileSplitInfo

    .PARAMETER FilePath
    Original file path

    .PARAMETER SplitCount
    Number of files to split into

    .PARAMETER OutputDirectory
    Directory to write output files

    .OUTPUTS
    Hashtable with Success, OutputFiles array, Error
    #>
    param(
        [Parameter(Mandatory=$true)][hashtable]$ScanResult,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][int]$SplitCount,
        [Parameter(Mandatory=$true)][string]$OutputDirectory
    )

    try {
        $ranges = Get-AlphabetRanges -SplitCount $SplitCount

        # Get base filename without extension
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $extension = [System.IO.Path]::GetExtension($FilePath)

        # Create buckets for messages
        $buckets = @()
        for ($i = 0; $i -lt $SplitCount; $i++) {
            $buckets += ,@(New-Object System.Collections.ArrayList)
        }

        # Distribute messages to buckets
        foreach ($messageData in $ScanResult.MessageData) {
            $bucket = Get-FileSplitBucket -LastName $messageData.LastName -SplitCount $SplitCount
            [void]$buckets[$bucket].Add($messageData.MessageText)
        }

        # Write output files
        $outputFiles = @()

        for ($i = 0; $i -lt $SplitCount; $i++) {
            $range = $ranges[$i]
            $outputFileName = "{0}_{1}{2}" -f $baseName, $range.Label, $extension
            $outputPath = [System.IO.Path]::Combine($OutputDirectory, $outputFileName)

            # Join messages with double newline (standard HL7 message separator)
            $content = $buckets[$i] -join "`r`n`r`n"

            # Write file (ASCII encoding for HL7)
            Set-Content -LiteralPath $outputPath -Value $content -Encoding ASCII

            $outputFiles += @{
                Path = $outputPath
                MessageCount = $buckets[$i].Count
            }
        }

        return @{
            Success = $true
            OutputFiles = $outputFiles
        }
    }
    catch {
        return @{
            Success = $false
            Error = "Error splitting HL7 file: $($_.Exception.Message)"
        }
    }
}


