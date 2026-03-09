# hl7-helpers.ps1
# Shared utilities for HL7 message processing

# Pre-compiled regex and lookup for HL7 escape sequence replacement (single-pass)
$script:Hl7EscapeRegex = [regex]::new('\\(X0D|X0A|E|F|S|T|R)\\', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:Hl7EscapeMap = @{
    'X0D' = "`r"
    'X0A' = "`n"
    'E'   = '\'
    'F'   = '|'
    'S'   = '^'
    'T'   = '&'
    'R'   = '~'
}

function Get-Hl7Field {
    param(
        [string]$Segment,
        [int]$FieldIndex
    )
    
    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return ""
    }
    
    $fields = $Segment -split '\|'
    if ($FieldIndex -lt $fields.Count) {
        return $fields[$FieldIndex]
    }
    return ""
}

function Get-Hl7Component {
    param(
        [string]$Field,
        [int]$ComponentIndex
    )
    
    if ([string]::IsNullOrWhiteSpace($Field)) {
        return ""
    }
    
    $components = $Field -split '\^'
    if ($ComponentIndex -lt $components.Count) {
        return $components[$ComponentIndex]
    }
    return ""
}

function ConvertFrom-Hl7Content {
    param(
        [string]$Content
    )
    
    # Use ArrayList for efficient appending
    $messages = New-Object System.Collections.ArrayList
    
    # Normalize line endings to just \n
    $Content = $Content -replace "`r`n", "`n"
    $Content = $Content -replace "`r", "`n"
    
    # Split content into individual messages by finding MSH segments
    $messageTexts = New-Object System.Collections.ArrayList
    $currentMessageLines = New-Object System.Collections.ArrayList
    
    $allLines = $Content -split "`n"
    
    foreach ($line in $allLines) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmedLine)) { continue }
        
        if ($trimmedLine.StartsWith("MSH|")) {
            # Start of a new message
            if ($currentMessageLines.Count -gt 0) {
                [void]$messageTexts.Add(($currentMessageLines -join "`n"))
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
        [void]$messageTexts.Add(($currentMessageLines -join "`n"))
    }
    
    for ($i = 0; $i -lt $messageTexts.Count; $i++) {
        $msg = $messageTexts[$i]
        
        # Parse segments
        $segments = @{}
        $allSegments = New-Object System.Collections.ArrayList
        $lines = $msg -split "`n"
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            if ([string]::IsNullOrEmpty($trimmedLine)) { continue }
            if ($trimmedLine.Length -lt 3) { continue }
            
            $segmentType = $trimmedLine.Substring(0, 3)
            if (-not $segments.ContainsKey($segmentType)) {
                $segments[$segmentType] = New-Object System.Collections.ArrayList
            }
            [void]$segments[$segmentType].Add($trimmedLine)
            [void]$allSegments.Add($trimmedLine)
        }
        
        $mshLine = if ($segments.ContainsKey("MSH")) { $segments["MSH"][0] } else { "" }
        $pidLine = if ($segments.ContainsKey("PID")) { $segments["PID"][0] } else { "" }
        $obrLine = if ($segments.ContainsKey("OBR")) { $segments["OBR"][0] } else { "" }
        
        $parsedPid = ConvertFrom-PidSegment -PidSegment $pidLine
        $parsedMsh = ConvertFrom-MshSegment -MshSegment $mshLine
        $parsedObr = ConvertFrom-ObrSegment -ObrSegment $obrLine
        
        [void]$messages.Add([PSCustomObject]@{
            Index = $i
            RawContent = $msg
            Segments = $segments
            AllSegments = $allSegments
            PatientId = $parsedPid.PatientId
            PatientName = $parsedPid.PatientName
            PatientLastName = $parsedPid.LastName
            PatientFirstName = $parsedPid.FirstName
            DateOfBirth = $parsedPid.DateOfBirth
            Sex = $parsedPid.Sex
            MessageType = $parsedMsh.MessageType
            MessageDateTime = $parsedMsh.MessageDateTime
            SendingApplication = $parsedMsh.SendingApplication
            SendingFacility = $parsedMsh.SendingFacility
            OrderDateTime = $parsedObr.OrderDateTime
            OrderingProvider = $parsedObr.OrderingProvider
        })
    }
    
    return $messages
}

function ConvertFrom-MshSegment {
    param(
        [string]$MshSegment
    )
    
    # Todo: check this against different HL7 version specifications
    # MSH fields (0-indexed after split by |):
    # 0: MSH
    # 1: ^~\& (encoding characters)
    # 2: Sending Application
    # 3: Sending Facility
    # 4: Receiving Application
    # 5: Receiving Facility
    # 6: Date/Time of Message
    # 7: Security (usually empty)
    # 8: Message Type (e.g., ORU^R01)
    # 9: Message Control ID
    
    $fields = $MshSegment -split '\|'
    
    return @{
        SendingApplication = if ($fields.Count -gt 2) { $fields[2] } else { "" }
        SendingFacility = if ($fields.Count -gt 3) { $fields[3] } else { "" }
        MessageDateTime = if ($fields.Count -gt 6) { $fields[6] } else { "" }
        MessageType = if ($fields.Count -gt 8) { $fields[8] } else { "" }
        MessageControlId = if ($fields.Count -gt 9) { $fields[9] } else { "" }
    }
}

function ConvertFrom-PidSegment {
    param(
        [string]$PidSegment
    )
    
    # Todo: check this against different HL7 version specifications
    # PID fields (0-indexed after split by |):
    # 0: PID
    # 1: Set ID
    # 2: Patient ID (external)
    # 3: Patient ID (internal list)
    # 4: Alternate Patient ID
    # 5: Patient Name (last^first^middle)
    # 6: Mother's Maiden Name
    # 7: Date of Birth
    # 8: Sex
    
    $fields = $PidSegment -split '\|'
    
    $patientId = if ($fields.Count -gt 3) { $fields[3] } else { "" }
    $patientNameField = if ($fields.Count -gt 5) { $fields[5] } else { "" }
    $dateOfBirth = if ($fields.Count -gt 7) { $fields[7] } else { "" }
    $sex = if ($fields.Count -gt 8) { $fields[8] } else { "" }
    
    $nameComponents = $patientNameField -split '\^'
    $lastName = if ($nameComponents.Count -gt 0) { $nameComponents[0] } else { "" }
    $firstName = if ($nameComponents.Count -gt 1) { $nameComponents[1] } else { "" }
    $middleName = if ($nameComponents.Count -gt 2) { $nameComponents[2] } else { "" }
    
    $patientName = "$lastName, $firstName"
    if (-not [string]::IsNullOrWhiteSpace($middleName)) {
        $patientName = "$lastName, $firstName $middleName"
    }
    
    return @{
        PatientId = $patientId
        PatientName = $patientName.Trim(", ")
        LastName = $lastName
        FirstName = $firstName
        MiddleName = $middleName
        DateOfBirth = $dateOfBirth
        Sex = $sex
    }
}

function ConvertFrom-ObrSegment {
    param(
        [string]$ObrSegment
    )
    
    # Todo: check this against different HL7 version specifications
    # OBR fields (0-indexed after split by |):
    # 0: OBR
    # 1: Set ID
    # 2: Placer Order Number
    # 3: Filler Order Number
    # 4: Universal Service ID
    # 5: Priority
    # 6: Requested Date/Time
    # 7: Observation Date/Time
    # ...
    # 16: Ordering Provider
    
    $fields = $ObrSegment -split '\|'
    
    $orderDateTime = if ($fields.Count -gt 7) { $fields[7] } else { "" }
    $orderingProviderField = if ($fields.Count -gt 16) { $fields[16] } else { "" }
    
    $providerComponents = $orderingProviderField -split '\^'
    $providerId = if ($providerComponents.Count -gt 0) { $providerComponents[0] } else { "" }
    $providerLast = if ($providerComponents.Count -gt 1) { $providerComponents[1] } else { "" }
    $providerFirst = if ($providerComponents.Count -gt 2) { $providerComponents[2] } else { "" }
    
    $orderingProvider = "$providerLast, $providerFirst"
    if (-not [string]::IsNullOrWhiteSpace($providerId)) {
        $orderingProvider = "$orderingProvider ($providerId)"
    }
    
    return @{
        OrderDateTime = $orderDateTime
        OrderingProvider = $orderingProvider.Trim(", ")
    }
}

function ConvertFrom-ObxSegments {
    param(
        [array]$ObxSegments
    )
    
    # Todo: check this against different HL7 version specifications
    # OBX fields (0-indexed after split by |):
    # 0: OBX
    # 1: Set ID
    # 2: Value Type
    # 3: Observation Identifier
    # 4: Observation Sub-ID
    # 5: Observation Value
    # 6: Units
    # 7: Reference Range
    # 8: Abnormal Flags
    
    $observations = @()
    
    foreach ($obx in $ObxSegments) {
        $fields = $obx -split '\|'
        
        $setId = if ($fields.Count -gt 1) { $fields[1] } else { "" }
        $valueType = if ($fields.Count -gt 2) { $fields[2] } else { "" }
        $observationId = if ($fields.Count -gt 3) { $fields[3] } else { "" }
        $observationValue = if ($fields.Count -gt 5) { $fields[5] } else { "" }
        $units = if ($fields.Count -gt 6) { $fields[6] } else { "" }
        $referenceRange = if ($fields.Count -gt 7) { $fields[7] } else { "" }
        $abnormalFlag = if ($fields.Count -gt 8) { $fields[8] } else { "" }
        
        $observations += [PSCustomObject]@{
            SetId = $setId
            ValueType = $valueType
            ObservationId = $observationId
            ObservationValue = $observationValue
            Units = $units
            ReferenceRange = $referenceRange
            AbnormalFlag = $abnormalFlag
        }
    }
    
    return $observations
}

function Format-Hl7DateTime {
    param(
        [string]$Hl7DateTime
    )
    
    if ([string]::IsNullOrWhiteSpace($Hl7DateTime)) {
        return ""
    }
    
    # HL7 datetime format: YYYYMMDDHHMMSS or YYYYMMDD
    try {
        if ($Hl7DateTime.Length -ge 8) {
            $year = $Hl7DateTime.Substring(0, 4)
            $month = $Hl7DateTime.Substring(4, 2)
            $day = $Hl7DateTime.Substring(6, 2)
            
            if ($Hl7DateTime.Length -ge 14) {
                $hour = $Hl7DateTime.Substring(8, 2)
                $minute = $Hl7DateTime.Substring(10, 2)
                $second = $Hl7DateTime.Substring(12, 2)
                return "$year-$month-$day $hour`:$minute`:$second"
            }
            return "$year-$month-$day"
        }
    }
    catch {
        # Return original if parsing fails
        $null = $_.Exception
    }
    
    return $Hl7DateTime
}

function Get-ObxTextContent {
    param(
        [array]$ObxSegments
    )
    
    if (-not $ObxSegments -or $ObxSegments.Count -eq 0) {
        return ""
    }
    
    $textLines = @()
    
    foreach ($obx in $ObxSegments) {
        $fields = $obx -split '\|'
        
        # OBX-5 is the observation value (index 5 after split by |)
        $observationValue = if ($fields.Count -gt 5) { $fields[5] } else { "" }
        
        # Skip empty OBX values - they're just spacers in HL7
        if ([string]::IsNullOrWhiteSpace($observationValue)) {
            continue
        }
        
        # Replace HL7 escape sequences in a single pass
        $observationValue = $script:Hl7EscapeRegex.Replace($observationValue, {
            param($m)
            $script:Hl7EscapeMap[$m.Groups[1].Value]
        })
        
        $textLines += $observationValue
    }
    
    # Join lines with newline
    return ($textLines -join "`r`n")
}

function Get-Obx3Component1 {
    <#
    .SYNOPSIS
    Extract the first component of OBX-3 (Observation Identifier)

    .PARAMETER ObxSegment
    The raw OBX segment string

    .OUTPUTS
    The first component of OBX-3 (before the ^ character)
    #>
    param(
        [string]$ObxSegment
    )

    if ([string]::IsNullOrWhiteSpace($ObxSegment)) {
        return ""
    }

    # OBX fields (0-indexed after split by |):
    # 0: OBX
    # 1: Set ID
    # 2: Value Type
    # 3: Observation Identifier (format: code^text^coding system)
    $fields = $ObxSegment -split '\|'

    if ($fields.Count -lt 4) {
        return ""
    }

    $obx3 = $fields[3]
    if ([string]::IsNullOrWhiteSpace($obx3)) {
        return ""
    }

    # Get first component (before ^)
    $components = $obx3 -split '\^'
    return $components[0].Trim()
}

function Select-ObxSegments {
    <#
    .SYNOPSIS
    Filter out OBX segments whose OBX-3.1 code matches the skip list

    .PARAMETER ObxSegments
    Array of raw OBX segment strings

    .PARAMETER SkipCodes
    Array of OBX-3.1 codes to skip (exclude)

    .OUTPUTS
    Filtered array of OBX segments
    #>
    param(
        [array]$ObxSegments,
        [array]$SkipCodes
    )

    if (-not $ObxSegments -or $ObxSegments.Count -eq 0) {
        return @()
    }

    if (-not $SkipCodes -or $SkipCodes.Count -eq 0) {
        return $ObxSegments
    }

    # Convert skip codes to uppercase for case-insensitive matching
    $skipCodesUpper = @($SkipCodes | ForEach-Object { $_.ToUpper() })

    $filtered = @()
    foreach ($obx in $ObxSegments) {
        $obx3Code = Get-Obx3Component1 -ObxSegment $obx
        $obx3CodeUpper = $obx3Code.ToUpper()

        if ($skipCodesUpper -notcontains $obx3CodeUpper) {
            $filtered += $obx
        }
    }

    return $filtered
}

function Get-FilteredObxTextContent {
    <#
    .SYNOPSIS
    Extract and combine OBX-5 text content after filtering by skip codes

    .PARAMETER ObxSegments
    Array of raw OBX segment strings

    .PARAMETER SkipCodes
    Array of OBX-3.1 codes to skip (exclude)

    .OUTPUTS
    Combined text from filtered OBX-5 values
    #>
    param(
        [array]$ObxSegments,
        [array]$SkipCodes
    )

    $filteredSegments = Select-ObxSegments -ObxSegments $ObxSegments -SkipCodes $SkipCodes
    return Get-ObxTextContent -ObxSegments $filteredSegments
}

