# diff-files.ps1
# File-level diff for NAACCR XML and HL7 files

function Test-NaaccrXmlFile {
    param(
        [string]$FilePath
    )

    if ((Get-Item $FilePath).Length -eq 0) {
        return @{
            IsValid = $false
            Error = "File is empty"
        }
    }

    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($FilePath)

        if ($xmlDoc.DocumentElement.LocalName -ne "NaaccrData") {
            return @{
                IsValid = $false
                Error = "Root element is not <NaaccrData>. Found: <$($xmlDoc.DocumentElement.LocalName)>"
            }
        }

        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "XML parsing error: $($_.Exception.Message)"
        }
    }
}

function Test-Hl7File {
    param(
        [string]$FilePath
    )

    if ((Get-Item $FilePath).Length -eq 0) {
        return @{
            IsValid = $false
            Error = "File is empty"
        }
    }

    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        $lineCount = 0
        $foundMsh = $false

        while ($lineCount -lt 5 -and -not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $lineCount++
            if ($line -match "^MSH\|") {
                $foundMsh = $true
                break
            }
        }
        $reader.Close()

        if (-not $foundMsh) {
            return @{
                IsValid = $false
                Error = "No MSH| segment found in first 5 lines. Not a valid HL7 file."
            }
        }

        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "Error reading file: $($_.Exception.Message)"
        }
    }
}

function Get-Hl7MessageHeaders {
    param(
        [string]$FilePath
    )

    $headers = New-Object System.Collections.ArrayList
    $content = Get-Content -Path $FilePath -Raw -Encoding ASCII
    $messages = $content -split "(?m)^MSH\|"
    $messages = $messages | Where-Object { $_ -match '\S' }

    $messageIndex = 0
    foreach ($msg in $messages) {
        $messageIndex++

        if (-not $msg.StartsWith("MSH|")) {
            $msg = "MSH|" + $msg
        }

        $mshMatch = [regex]::Match($msg, "(?m)^MSH\|([^\r\n]+)")
        $mshLine = if ($mshMatch.Success) { $mshMatch.Groups[1].Value } else { "" }

        $pidMatch = [regex]::Match($msg, "(?m)^PID\|([^\r\n]+)")
        $pidLine = if ($pidMatch.Success) { $pidMatch.Groups[1].Value } else { "" }

        # Parse MSH fields (fields are 0-indexed after the initial MSH|)
        # MSH|^~\&|sendApp|sendFac|recvApp|recvFac|datetime|security|messageType|messageControlId|...
        # After split on |: 0=encoding(^~\&), 1=sendApp, 2=sendFac, 3=recvApp, 4=recvFac,
        #                   5=datetime, 6=security, 7=messageType(MSH-9), 8=messageControlId(MSH-10)
        $mshFields = if ($mshLine) { $mshLine -split '\|' } else { @() }
        $messageType = if ($mshFields.Count -gt 7) { $mshFields[7] } else { "" }
        $messageControlId = if ($mshFields.Count -gt 8) { $mshFields[8] } else { "" }

        # Parse PID fields
        # PID|setId|externalId|patientId|altPatientId|patientName|motherMaidenName|dob|...
        # After split: 0=setId, 1=externalId, 2=patientId(PID-3), 3=altPatientId,
        #              4=patientName(PID-5), 5=motherMaidenName, 6=dob(PID-7)
        $pidFields = if ($pidLine) { $pidLine -split '\|' } else { @() }
        $patientId = if ($pidFields.Count -gt 2) { $pidFields[2] } else { "" }
        $patientName = if ($pidFields.Count -gt 4) { $pidFields[4] } else { "" }
        $dob = if ($pidFields.Count -gt 6) { $pidFields[6] } else { "" }

        # Parse patient name (format: LastName^FirstName^MiddleName...)
        $nameParts = $patientName -split '\^'
        $lastName = if ($nameParts.Count -gt 0) { $nameParts[0] } else { "" }
        $firstName = if ($nameParts.Count -gt 1) { $nameParts[1] } else { "" }

        [void]$headers.Add(@{
            MessageIndex     = $messageIndex
            PatientId        = $patientId
            PatientLastName  = $lastName
            PatientFirstName = $firstName
            DateOfBirth      = $dob
            MessageControlId = $messageControlId
            MessageType      = $messageType
            RawMessage       = $msg
        })
    }

    return $headers
}

function Get-Hl7MessageKey {
    param(
        [hashtable]$MessageHeader
    )

    if (-not [string]::IsNullOrWhiteSpace($MessageHeader.MessageControlId)) {
        return $MessageHeader.MessageControlId
    }

    $key = ""
    if (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientId)) {
        $key = $MessageHeader.PatientId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientLastName)) {
        $key = $MessageHeader.PatientLastName
        if (-not [string]::IsNullOrWhiteSpace($MessageHeader.PatientFirstName)) {
            $key += "^" + $MessageHeader.PatientFirstName
        }
        if (-not [string]::IsNullOrWhiteSpace($MessageHeader.DateOfBirth)) {
            $key += "^" + $MessageHeader.DateOfBirth
        }
    }

    if ([string]::IsNullOrWhiteSpace($key)) {
        return "MSG-$($MessageHeader.MessageIndex)"
    }

    return "$key-MSG$($MessageHeader.MessageIndex)"
}

function Compare-Hl7Files {
    param(
        [string]$FilePathA,
        [string]$FilePathB,
        [string]$Method = "Index"  # "Index" or "Key"
    )

    $headersA = Get-Hl7MessageHeaders -FilePath $FilePathA
    $headersB = Get-Hl7MessageHeaders -FilePath $FilePathB

    $comparisons = @()

    if ($Method -eq "Index") {
        $maxCount = [Math]::Max($headersA.Count, $headersB.Count)

        for ($i = 0; $i -lt $maxCount; $i++) {
            $msgA = if ($i -lt $headersA.Count) { $headersA[$i] } else { $null }
            $msgB = if ($i -lt $headersB.Count) { $headersB[$i] } else { $null }

            if ($null -ne $msgA -and $null -ne $msgB) {
                $rawA = $msgA.RawMessage -replace '\s+', ' '
                $rawB = $msgB.RawMessage -replace '\s+', ' '
                $isSame = $rawA -eq $rawB

                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = $msgB.PatientId
                    Status         = if ($isSame) { "Same" } else { "Different Content" }
                    InFileA        = $true
                    InFileB        = $true
                    NameA          = $nameA
                    NameB          = $nameB
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = $msgB.MessageType
                }
            }
            elseif ($null -ne $msgA) {
                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = ""
                    Status         = "OnlyInA"
                    InFileA        = $true
                    InFileB        = $false
                    NameA          = $nameA
                    NameB          = ""
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = ""
                }
            }
            else {
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $i + 1
                    PatientIdA     = ""
                    PatientIdB     = $msgB.PatientId
                    Status         = "OnlyInB"
                    InFileA        = $false
                    InFileB        = $true
                    NameA          = ""
                    NameB          = $nameB
                    MessageTypeA   = ""
                    MessageTypeB   = $msgB.MessageType
                }
            }
        }
    }
    else {
        $mapA = @{}
        $mapB = @{}

        foreach ($header in $headersA) {
            $msgKey = Get-Hl7MessageKey -MessageHeader $header
            $mapA[$msgKey] = $header
        }

        foreach ($header in $headersB) {
            $msgKey = Get-Hl7MessageKey -MessageHeader $header
            $mapB[$msgKey] = $header
        }

        $allMessageKeys = New-Object System.Collections.Generic.HashSet[string]
        foreach ($key in $mapA.Keys) { [void]$allMessageKeys.Add($key) }
        foreach ($key in $mapB.Keys) { [void]$allMessageKeys.Add($key) }

        foreach ($msgKey in $allMessageKeys) {
            $inA = $mapA.ContainsKey($msgKey)
            $inB = $mapB.ContainsKey($msgKey)

            if ($inA -and $inB) {
                $msgA = $mapA[$msgKey]
                $msgB = $mapB[$msgKey]

                $rawA = $msgA.RawMessage -replace '\s+', ' '
                $rawB = $msgB.RawMessage -replace '\s+', ' '
                $isSame = $rawA -eq $rawB

                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgA.MessageIndex
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = $msgB.PatientId
                    Status         = if ($isSame) { "Same" } else { "Different Content" }
                    InFileA        = $true
                    InFileB        = $true
                    NameA          = $nameA
                    NameB          = $nameB
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = $msgB.MessageType
                }
            }
            elseif ($inA) {
                $msgA = $mapA[$msgKey]
                $nameA = if ($msgA.PatientLastName -or $msgA.PatientFirstName) {
                    "$($msgA.PatientLastName), $($msgA.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgA.MessageIndex
                    PatientIdA     = $msgA.PatientId
                    PatientIdB     = ""
                    Status         = "OnlyInA"
                    InFileA        = $true
                    InFileB        = $false
                    NameA          = $nameA
                    NameB          = ""
                    MessageTypeA   = $msgA.MessageType
                    MessageTypeB   = ""
                }
            }
            else {
                $msgB = $mapB[$msgKey]
                $nameB = if ($msgB.PatientLastName -or $msgB.PatientFirstName) {
                    "$($msgB.PatientLastName), $($msgB.PatientFirstName)"
                } else { "" }

                $comparisons += @{
                    Index          = $msgB.MessageIndex
                    PatientIdA     = ""
                    PatientIdB     = $msgB.PatientId
                    Status         = "OnlyInB"
                    InFileA        = $false
                    InFileB        = $true
                    NameA          = ""
                    NameB          = $nameB
                    MessageTypeA   = ""
                    MessageTypeB   = $msgB.MessageType
                }
            }
        }
    }

    $comparisons = $comparisons | Sort-Object { $_.Index }

    $stats = @{
        TotalMessagesA = $headersA.Count
        TotalMessagesB = $headersB.Count
        Same           = ($comparisons | Where-Object { $_.Status -eq "Same" }).Count
        Different      = ($comparisons | Where-Object { $_.Status -eq "Different Content" }).Count
        OnlyInA        = ($comparisons | Where-Object { $_.Status -eq "OnlyInA" }).Count
        OnlyInB        = ($comparisons | Where-Object { $_.Status -eq "OnlyInB" }).Count
    }

    return @{
        Comparisons = $comparisons
        Stats       = $stats
        Method      = $Method
    }
}

function Compare-XmlFiles {
    param(
        [string]$FilePathA,
        [string]$FilePathB
    )

    $xmlDocA = New-Object System.Xml.XmlDocument
    $xmlDocA.Load($FilePathA)

    $xmlDocB = New-Object System.Xml.XmlDocument
    $xmlDocB.Load($FilePathB)

    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDocA.NameTable)
    $nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml")

    $patientsA = $xmlDocA.SelectNodes("//n:Patient", $nsMgr)
    $patientsB = $xmlDocB.SelectNodes("//n:Patient", $nsMgr)

    $comparisons = @()
    $maxCount = [Math]::Max($patientsA.Count, $patientsB.Count)

    for ($i = 0; $i -lt $maxCount; $i++) {
        $patientA = if ($i -lt $patientsA.Count) { $patientsA[$i] } else { $null }
        $patientB = if ($i -lt $patientsB.Count) { $patientsB[$i] } else { $null }

        if ($null -ne $patientA -and $null -ne $patientB) {
            $isSame = Compare-PatientRecords -PatientA $patientA -PatientB $patientB -NsMgr $nsMgr

            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = if ($isSame) { "Same" } else { "Different Content" }
                InFileA = $true
                InFileB = $true
                PatientA = $patientA
                PatientB = $patientB
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
        elseif ($null -ne $patientA) {
            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = "OnlyInA"
                InFileA = $true
                InFileB = $false
                PatientA = $patientA
                PatientB = $null
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = ""
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = 0
            }
        }
        else {
            $comparisons += @{
                Index = $i + 1
                PatientId = $i + 1
                Status = "OnlyInB"
                InFileA = $false
                InFileB = $true
                PatientA = $null
                PatientB = $patientB
                NameA = ""
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = 0
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
    }

    $stats = @{
        TotalPatientsA = $patientsA.Count
        TotalPatientsB = $patientsB.Count
        Same = ($comparisons | Where-Object { $_.Status -eq "Same" }).Count
        Different = ($comparisons | Where-Object { $_.Status -eq "Different Content" }).Count
        OnlyInA = ($comparisons | Where-Object { $_.Status -eq "OnlyInA" }).Count
        OnlyInB = ($comparisons | Where-Object { $_.Status -eq "OnlyInB" }).Count
    }

    return @{
        Comparisons = $comparisons
        Stats = $stats
        NsMgr = $nsMgr
    }
}

function Get-PatientKey {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    # Use name + DOB as key (patientIdNumber is just a file-specific sequence number)
    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
    $dob = $Patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $NsMgr)

    $key = ""
    if ($lastName) { $key += $lastName.InnerText }
    if ($firstName) { $key += "|" + $firstName.InnerText }
    if ($dob) { $key += "|" + $dob.InnerText }

    if (-not [string]::IsNullOrWhiteSpace($key)) {
        return $key
    }

    $patientIdNode = $Patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $NsMgr)
    if ($null -ne $patientIdNode -and -not [string]::IsNullOrWhiteSpace($patientIdNode.InnerText)) {
        return $patientIdNode.InnerText
    }

    return [guid]::NewGuid().ToString()
}

function Get-PatientName {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)

    $name = ""
    if ($lastName) { $name = $lastName.InnerText }
    if ($firstName) {
        if ($name) { $name += ", " }
        $name += $firstName.InnerText
    }

    return $name
}

function Compare-PatientRecords {
    param(
        [System.Xml.XmlElement]$PatientA,
        [System.Xml.XmlElement]$PatientB,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $linesA = Get-FormattedPatientXml -Patient $PatientA
    $linesB = Get-FormattedPatientXml -Patient $PatientB

    if ($linesA.Count -ne $linesB.Count) {
        return $false
    }

    for ($i = 0; $i -lt $linesA.Count; $i++) {
        if ($linesA[$i] -ne $linesB[$i]) {
            return $false
        }
    }

    return $true
}

function Get-FormattedPatientXml {
    param(
        [System.Xml.XmlElement]$Patient
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`n"
    $settings.OmitXmlDeclaration = $true

    $sw = New-Object System.IO.StringWriter
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $Patient.WriteTo($xw)
    $xw.Flush()
    $xw.Close()

    $formatted = $sw.ToString()
    $sw.Close()

    $lines = @($formatted -split "`n" | ForEach-Object { $_.TrimEnd("`r", " ") })
    return $lines
}

function Get-FormattedXmlLines {
    param(
        [string]$FilePath
    )

    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.PreserveWhitespace = $false
        $xmlDoc.Load($FilePath)

        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.IndentChars = "  "
        $settings.NewLineChars = "`n"
        $settings.NewLineHandling = "Replace"
        $settings.OmitXmlDeclaration = $false

        $sw = New-Object System.IO.StringWriter
        $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
        $xmlDoc.Save($xw)
        $xw.Flush()
        $xw.Close()

        $formattedXml = $sw.ToString()
        $sw.Close()

        $lines = @($formattedXml -split "`n" | ForEach-Object { $_.TrimEnd("`r") })

        return ,$lines
    }
    catch {
        throw "Error formatting XML: $($_.Exception.Message)"
    }
}
