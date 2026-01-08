# hl7-helpers.ps1
# Shared utilities for HL7 message processing

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

function Parse-Hl7Messages {
    param(
        [string]$Content
    )
    
    $messages = @()
    
    # Normalize line endings to just \n
    $Content = $Content -replace "`r`n", "`n"
    $Content = $Content -replace "`r", "`n"
    
    # Split content into individual messages by finding MSH segments
    # Each message starts with "MSH|"
    $messageTexts = @()
    $currentMessage = ""
    
    $allLines = $Content -split "`n"
    
    foreach ($line in $allLines) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmedLine)) { continue }
        
        if ($trimmedLine.StartsWith("MSH|")) {
            # Start of a new message
            if (-not [string]::IsNullOrEmpty($currentMessage)) {
                $messageTexts += $currentMessage
            }
            $currentMessage = $trimmedLine
        }
        else {
            # Continue current message
            if (-not [string]::IsNullOrEmpty($currentMessage)) {
                $currentMessage += "`n" + $trimmedLine
            }
        }
    }
    
    # Don't forget the last message
    if (-not [string]::IsNullOrEmpty($currentMessage)) {
        $messageTexts += $currentMessage
    }
    
    # Parse each message
    for ($i = 0; $i -lt $messageTexts.Count; $i++) {
        $msg = $messageTexts[$i]
        
        # Parse segments
        $segments = @{}
        $allSegments = @()
        $lines = $msg -split "`n"
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            if ([string]::IsNullOrEmpty($trimmedLine)) { continue }
            if ($trimmedLine.Length -lt 3) { continue }
            
            $segmentType = $trimmedLine.Substring(0, 3)
            if (-not $segments.ContainsKey($segmentType)) {
                $segments[$segmentType] = @()
            }
            $segments[$segmentType] += $trimmedLine
            $allSegments += $trimmedLine
        }
        
        # Extract common fields
        $mshLine = if ($segments.ContainsKey("MSH")) { $segments["MSH"][0] } else { "" }
        $pidLine = if ($segments.ContainsKey("PID")) { $segments["PID"][0] } else { "" }
        $obrLine = if ($segments.ContainsKey("OBR")) { $segments["OBR"][0] } else { "" }
        
        $parsedPid = Parse-PidSegment -PidSegment $pidLine
        $parsedMsh = Parse-MshSegment -MshSegment $mshLine
        $parsedObr = Parse-ObrSegment -ObrSegment $obrLine
        
        $messages += [PSCustomObject]@{
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
        }
    }
    
    return $messages
}

function Parse-MshSegment {
    param(
        [string]$MshSegment
    )
    
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

function Parse-PidSegment {
    param(
        [string]$PidSegment
    )
    
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
    
    # Parse name components (last^first^middle)
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

function Parse-ObrSegment {
    param(
        [string]$ObrSegment
    )
    
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
    
    # Parse ordering provider (id^last^first)
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

function Parse-ObxSegments {
    param(
        [array]$ObxSegments
    )
    
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
    }
    
    return $Hl7DateTime
}

function Extract-ObxTextContent {
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
        
        # Handle HL7 escape sequences if present
        # Common ones: \X0D\ = carriage return, \X0A\ = line feed, \E\ = escape, \F\ = field separator
        $observationValue = $observationValue -replace '\\X0D\\', "`r"
        $observationValue = $observationValue -replace '\\X0A\\', "`n"
        $observationValue = $observationValue -replace '\\E\\', '\'
        $observationValue = $observationValue -replace '\\F\\', '|'
        $observationValue = $observationValue -replace '\\S\\', '^'
        $observationValue = $observationValue -replace '\\T\\', '&'
        $observationValue = $observationValue -replace '\\R\\', '~'
        
        $textLines += $observationValue
    }
    
    # Join lines with newline
    return ($textLines -join "`r`n")
}

