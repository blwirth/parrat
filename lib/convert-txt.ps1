# convert-hl7.ps1
# Module for converting pathology text files to HL7 format

#region Facility Configuration
$script:FacilityConfig = @{
    'Parkland' = @{
        FacilityNum = '7120090'
        CLIA = 'PARKLAND MEDICAL CENTER^300017^CLIA'
    }
    'Portsmouth' = @{
        FacilityNum = '7120360'
        CLIA = 'PORTSMOUTH REGIONAL HOSPITAL^30D1064878^CLIA'
    }
    'Frisbie' = @{
        FacilityNum = '7120380'
        CLIA = 'FRISBIE MEMORIAL HOSPITAL^300014^CLIA'
    }
    'SJH' = @{
        FacilityNum = '120300'
        CLIA = 'ST JOSEPH HOSPITAL^30D0896420^CLIA'
    }
}

$script:UnknownDate = '99999999'
#endregion

#region Helper Functions
function Convert-DateToHL7 {
    param(
        [string]$DateString,
        [string]$Format = 'MM/dd/yyyy'
    )
    
    if ([string]::IsNullOrWhiteSpace($DateString)) {
        return $script:UnknownDate
    }
    
    try {
        # Handle 2-digit or 4-digit years
        if ($DateString -match '^\d{2}/\d{2}/\d{2}$') {
            # 2-digit year format (MM/dd/yy)
            $date = [DateTime]::ParseExact($DateString, 'MM/dd/yy', $null)
        } else {
            # 4-digit year format (MM/dd/yyyy)
            $date = [DateTime]::ParseExact($DateString, 'MM/dd/yyyy', $null)
        }
        return $date.ToString('yyyyMMdd')
    } catch {
        Write-Warning "Could not parse date '$DateString': $_"
        return $script:UnknownDate
    }
}

function Parse-PatientLine {
    param([string]$Line)
    
    $result = @{
        NameLast = ''
        NameFirst = ''
        NameMiddle = ''
        BirthDate = ''
        Sex = ''
        MedicalRecordNumber = ''
    }
    
    # Remove commas, replace with spaces
    $cleanLine = $Line -replace ',', ' '
    
    # Extract name (between PATIENT: and ACCT)
    if ($cleanLine -match 'PATIENT:\s*(.+?)\s+ACCT') {
        $fullName = $matches[1].Trim()
        $nameParts = $fullName -split '\s+'
        $result.NameLast = $nameParts[0]
        if ($nameParts.Length -gt 1) { $result.NameFirst = $nameParts[1] }
        if ($nameParts.Length -gt 2) { $result.NameMiddle = $nameParts[2] }
    }
    
    # Extract DOB
    if ($cleanLine -match 'DOB:\s*(\d{2}/\d{2}/\d{4})') {
        $result.BirthDate = $matches[1]
    }
    
    # Extract Sex
    if ($cleanLine -match 'AGE/SEX:\s*\d+/([A-Z])') {
        $result.Sex = $matches[1]
    }
    
    # Extract Medical Record Number
    if ($cleanLine -match 'U:\s*([A-Z]\d+)') {
        $result.MedicalRecordNumber = $matches[1]
    }
    
    return $result
}

function Parse-SpecimenDate {
    param([string]$Line)
    
    if ($Line -match 'COLL:\s*(\d{2}/\d{2}/\d{2,4})') {
        return $matches[1]
    }
    return ''
}

function Parse-PathReportID {
    param([string]$Line)
    
    if ($Line -match 'SPEC\s*[:#]\s*(?:.*?:)?(\S+)\s+COLL:') {
        return $matches[1]
    }
    return ''
}

function Build-MSHSegment {
    param(
        [int]$CaseNumber,
        [string]$CLIA,
        [string]$TransmitDate = $script:UnknownDate
    )
    
    return "MSH|^~\&|E-Path Case=$CaseNumber|$CLIA|E-Path|NHSCR|$TransmitDate||ORU^R01^ORU_R01||P|2.5.1|||||USA||ENG||VOL_V_40_ORU_R01^NAACCR_CP"
}

function Build-PIDSegment {
    param(
        [hashtable]$PatientData,
        [string]$BirthDateHL7
    )
    
    $mrn = $PatientData.MedicalRecordNumber
    $last = $PatientData.NameLast
    $first = $PatientData.NameFirst
    $middle = $PatientData.NameMiddle
    $sex = $PatientData.Sex
    
    return "PID|1||$mrn^^^^MR^~^^^^SS||$last^$first^$middle||$BirthDateHL7|$sex|||Unknown^^Unknown^ZZ^99999|||"
}

function Build-OBRSegment {
    param(
        [string]$PathReportID,
        [string]$SpecimenDateHL7
    )
    
    # Removed the unknown physician--useless info--but will keep below comment for position reference if we want to parse it eventually
    # Original format: "OBR|1||$PathReportID||||$SpecimenDateHL7|||||||||^physicianNameLast^physicianNameFirst^physicianNameMiddle|||||||||F||||||||"
    return "OBR|1||$PathReportID||||$SpecimenDateHL7||||||||||||||||||F||||||||"
}

function Build-OBXSegment {
    param(
        [int]$LineNumber,
        [string]$TextLine
    )
    
    return "OBX|$LineNumber|TX|||$TextLine"
}

#region SJH-Specific Helper Functions
function Parse-SJH-MinDateFromLine {
    param([string]$Line)
    
    # Match M/D/YY, MM/DD/YY, M/D/YYYY, MM/DD/YYYY
    $dateRe = [regex]'\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b'
    $dateMatches = $dateRe.Matches($Line)
    if ($dateMatches.Count -eq 0) { return $null }
    
    $dates = foreach ($m in $dateMatches) {
        $s = $m.Groups[1].Value
        $dt = $null
        # Try common parse formats
        $formats = @('M/d/yy','MM/dd/yy','M/d/yyyy','MM/dd/yyyy')
        if ([DateTime]::TryParseExact($s, $formats, $null, [Globalization.DateTimeStyles]::None, [ref]$dt)) {
            $dt
        } else {
            # Fall back
            if ([DateTime]::TryParse($s, [ref]$dt)) { $dt }
        }
    }
    
    $dates = $dates | Where-Object { $_ -is [DateTime] }
    if (-not $dates) { return $null }
    return ($dates | Sort-Object | Select-Object -First 1)
}

function Parse-SJH-PatientLine {
    param([string]$Line)
    
    $result = @{
        NameLast = ''
        NameFirst = ''
        NameMiddle = ''
        Sex = ''
        Age = $null
    }
    
    # Name pattern: Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?
    $nameRe = [regex]'Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?(?=\s*(?:Age:|\d{4,7}\b|MD:|MRN:|$))'
    $m = $nameRe.Match($Line)
    if ($m.Success) {
        $result.NameLast = $m.Groups[1].Value
        $result.NameFirst = $m.Groups[2].Value
        if ($m.Groups.Count -ge 4 -and $m.Groups[3].Value) {
            $result.NameMiddle = $m.Groups[3].Value
        }
    }
    
    # Sex pattern: Sex:\s*([MF])\b
    $sexRe = [regex]'Sex:\s*([MF])\b'
    $m = $sexRe.Match($Line)
    if ($m.Success) {
        $result.Sex = $m.Groups[1].Value
    }
    
    # Age pattern: Age:\s*(\d{1,3})\b
    $ageRe = [regex]'Age:\s*(\d{1,3})\b'
    $m = $ageRe.Match($Line)
    if ($m.Success) {
        $result.Age = [int]$m.Groups[1].Value
    }
    
    return $result
}

function Parse-SJH-MRN {
    param([string]$Line)
    
    # MRN pattern: (?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))
    $mrnRe = [regex]'(?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))'
    $m = $mrnRe.Match($Line)
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return ''
}

function Parse-SJH-PathReportID {
    param([string]$Line)
    
    # Path report ID pattern: \b(NH|NS|NC)2[0-9]-\d+\b
    $pathIdRe = [regex]'\b(NH|NS|NC)2[0-9]-\d+\b'
    $m = $pathIdRe.Match($Line)
    if ($m.Success) {
        return $m.Value
    }
    return ''
}

function Derive-SJH-DOB {
    param(
        [int]$Age,
        [DateTime]$SpecimenDate
    )
    
    if ($Age -and $SpecimenDate) {
        $dobYear = $SpecimenDate.Year - $Age
        if ($dobYear -ge 1800 -and $dobYear -le 2200) {
            return ('{0}9999' -f $dobYear.ToString('0000'))
        }
    }
    return $script:UnknownDate
}

function Normalize-SJH-Whitespace {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return ([regex]::Replace($s.Trim(), '\s+', ' '))
}
#endregion

#endregion

#region Parsing Functions
function Parse-Standard-Cases {
    param(
        [string]$InputPath,
        [string]$FacilityName
    )
    
    # Read input file
    $lines = Get-Content $InputPath -Encoding UTF8
    
    # Storage for parsed cases
    $cases = [System.Collections.ArrayList]::new()
    $currentCase = $null
    $caseNumber = 0
    $linesSinceCaseSigned = 999  # Track how many lines since "Case Signed At"
    
    foreach ($line in $lines) {
        $line = $line.Trim()
        
        # Skip blank lines and continuation markers
        if ([string]::IsNullOrWhiteSpace($line) -or $line -eq '** CONTINUED ON NEXT PAGE **') {
            continue
        }
        
        # Track if we see "Case Signed At"
        if ($line -match '^Case Signed At$') {
            $linesSinceCaseSigned = 0
        } else {
            $linesSinceCaseSigned++
        }
        
        # Check if this line starts a new case (facility name at start)
        # Don't start new case if we're within 4 lines after "Case Signed At"
        $isFacilityLine = $line -match "^$FacilityName"
        
        if ($isFacilityLine -and $linesSinceCaseSigned -le 4) {
            # We're in the "Case Signed At" block, so this is NOT a new case
            $isFacilityLine = $false
        }
        
        if ($isFacilityLine) {
            # Save previous case if exists
            if ($currentCase) {
                [void]$cases.Add($currentCase)
            }
            
            # Start new case
            $caseNumber++
            $currentCase = @{
                CaseNumber = $caseNumber
                PatientData = @{
                    NameLast = ''
                    NameFirst = ''
                    NameMiddle = ''
                    BirthDate = ''
                    Sex = ''
                    MedicalRecordNumber = ''
                }
                SpecimenDate = ''
                PathReportID = ''
                TextLines = [System.Collections.ArrayList]::new()
            }
            
            # Reset the counter since we're starting a fresh case
            $linesSinceCaseSigned = 999
        }
        
        if ($null -eq $currentCase) {
            continue
        }
        
        # Parse patient information from PATIENT: line
        if ($line -match '^PATIENT:') {
            $patientInfo = Parse-PatientLine $line
            $currentCase.PatientData = $patientInfo
        }
        
        # Parse specimen date from any line containing it
        $specimenDate = Parse-SpecimenDate $line
        if ($specimenDate) {
            $currentCase.SpecimenDate = $specimenDate
        }
        
        # Parse path report ID from any line containing it
        $pathReportID = Parse-PathReportID $line
        if ($pathReportID) {
            $currentCase.PathReportID = $pathReportID
        }
        
        # Add line to case text
        [void]$currentCase.TextLines.Add($line)
    }
    
    # Don't forget the last case
    if ($currentCase) {
        [void]$cases.Add($currentCase)
    }
    
    return $cases
}

function Parse-SJH-Cases {
    param([string]$InputPath)
    
    # Read and preprocess input file
    $rawText = [System.IO.File]::ReadAllText($InputPath, [System.Text.Encoding]::Default)
    
    # Normalize case boundaries by inserting newlines before embedded IDs
    $yy = ([DateTime]::Now.Year % 100).ToString('00')
    $boundaryPattern = "(?<!\r?\n)(?=N[A-Z]($yy|22|23|24)-\d{1,6}\s+(Patient:|MRN:))"
    $normalized = [regex]::Replace($rawText, $boundaryPattern, "`r`n")
    
    # Split to lines
    $lines = $normalized -split "\r?\n"
    
    # Skip line prefixes
    $skipPrefixes = @(
        'Tissue Committee Report',
        'Date/Time Printed:',
        'Selection Criteria:',
        'Part Type:'
    )
    
    # Case detection regex
    $caseStartRe = [regex]'^\s*(?:NH|NS|NC)2[0-9]-\d+'
    
    # Storage for parsed cases
    $cases = [System.Collections.ArrayList]::new()
    $caseNumber = 0
    
    # Current case state
    $currentCase = $null
    
    foreach ($line0 in $lines) {
        $line = Normalize-SJH-Whitespace $line0
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Skip unwanted lines
        $skip = $false
        foreach ($p in $skipPrefixes) {
            if ($line.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }
        
        # Check for case boundary
        if ($caseStartRe.IsMatch($line)) {
            # Save previous case if exists
            if ($currentCase) {
                [void]$cases.Add($currentCase)
            }
            
            # Start new case
            $caseNumber++
            $currentCase = @{
                CaseNumber = $caseNumber
                PatientData = @{
                    NameLast = ''
                    NameFirst = ''
                    NameMiddle = ''
                    BirthDate = ''
                    Sex = ''
                    MedicalRecordNumber = ''
                }
                SpecimenDate = ''
                PathReportID = ''
                TextLines = [System.Collections.ArrayList]::new()
                Age = $null
                SpecimenDateObj = $null
            }
        }
        
        if ($null -eq $currentCase) {
            continue
        }
        
        # Parse patient name, sex, age from line
        $patientInfo = Parse-SJH-PatientLine $line
        if ($patientInfo.NameLast) {
            $currentCase.PatientData.NameLast = $patientInfo.NameLast
            $currentCase.PatientData.NameFirst = $patientInfo.NameFirst
            $currentCase.PatientData.NameMiddle = $patientInfo.NameMiddle
        }
        if ($patientInfo.Sex) {
            $currentCase.PatientData.Sex = $patientInfo.Sex
        }
        if ($patientInfo.Age) {
            $currentCase.Age = $patientInfo.Age
        }
        
        # Parse MRN
        $mrn = Parse-SJH-MRN $line
        if ($mrn) {
            $currentCase.PatientData.MedicalRecordNumber = $mrn
        }
        
        # Parse path report ID
        $pathID = Parse-SJH-PathReportID $line
        if ($pathID) {
            $currentCase.PathReportID = $pathID
        }
        
        # Parse specimen date (earliest date on line)
        $minDate = Parse-SJH-MinDateFromLine $line
        if ($minDate) {
            $currentCase.SpecimenDateObj = $minDate
            $currentCase.SpecimenDate = $minDate.ToString('MM/dd/yyyy')
        }
        
        # Add line to text
        [void]$currentCase.TextLines.Add($line)
    }
    
    # Save final case
    if ($currentCase) {
        [void]$cases.Add($currentCase)
    }
    
    # Derive DOB for each case
    foreach ($case in $cases) {
        if ($case.Age -and $case.SpecimenDateObj) {
            $case.PatientData.BirthDate = Derive-SJH-DOB -Age $case.Age -SpecimenDate $case.SpecimenDateObj
        }
    }
    
    return $cases
}
#endregion

#region Main Conversion Function
function Convert-PathologyTextToHL7 {
    <#
    .SYNOPSIS
        Converts pathology text file to HL7 format
    
    .PARAMETER InputPath
        Path to input text file (Level_1 format)
    
    .PARAMETER OutputPath
        Path for output HL7 file (Level_2 format)
    
    .PARAMETER FacilityName
        Name of facility (Parkland, Portsmouth, Frisbie, or SJH)
    
    .PARAMETER PreviewOnly
        If specified, returns parsed data without writing output file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Parkland', 'Portsmouth', 'Frisbie', 'SJH')]
        [string]$FacilityName,
        
        [switch]$PreviewOnly
    )
    
    # Validate input file exists
    if (-not (Test-Path $InputPath)) {
        throw "Input file not found: $InputPath"
    }
    
    # Get facility configuration
    $facilityConfig = $script:FacilityConfig[$FacilityName]
    if (-not $facilityConfig) {
        throw "Unknown facility: $FacilityName"
    }
    
    # Storage for parsed cases
    $cases = [System.Collections.ArrayList]::new()
    
    # Branch based on facility type
    if ($FacilityName -eq 'SJH') {
        # SJH-specific parsing logic
        $cases = Parse-SJH-Cases -InputPath $InputPath
    } else {
        # Standard facility parsing logic (Parkland, Portsmouth, Frisbie)
        $cases = Parse-Standard-Cases -InputPath $InputPath -FacilityName $FacilityName
    }
    
    # Preview mode - return parsed data
    if ($PreviewOnly) {
        return @{
            Cases = $cases
            FacilityConfig = $facilityConfig
            InputPath = $InputPath
        }
    }
    
    # Generate HL7 output
    $hl7Lines = [System.Collections.ArrayList]::new()
    
    foreach ($case in $cases) {
        # Convert dates to HL7 format
        # For SJH, BirthDate is already in HL7 format (YYYY9999)
        if ($FacilityName -eq 'SJH') {
            $birthDateHL7 = $case.PatientData.BirthDate
            if ($case.SpecimenDateObj) {
                $specimenDateHL7 = $case.SpecimenDateObj.ToString('yyyyMMdd')
            } else {
                $specimenDateHL7 = $script:UnknownDate
            }
        } else {
            $birthDateHL7 = Convert-DateToHL7 $case.PatientData.BirthDate
            $specimenDateHL7 = Convert-DateToHL7 $case.SpecimenDate
        }
        
        # Build segments
        $mshSegment = Build-MSHSegment -CaseNumber $case.CaseNumber -CLIA $facilityConfig.CLIA
        $pidSegment = Build-PIDSegment -PatientData $case.PatientData -BirthDateHL7 $birthDateHL7
        $obrSegment = Build-OBRSegment -PathReportID $case.PathReportID -SpecimenDateHL7 $specimenDateHL7
        
        [void]$hl7Lines.Add($mshSegment)
        [void]$hl7Lines.Add($pidSegment)
        [void]$hl7Lines.Add($obrSegment)
        
        # Add text lines as OBX segments
        # For SJH: drop the first OBX (patient info line) and renumber remaining from 1
        if ($FacilityName -eq 'SJH') {
            if ($case.TextLines.Count -gt 1) {
                for ($i = 1; $i -lt $case.TextLines.Count; $i++) {
                    $obxSegment = Build-OBXSegment -LineNumber ($i) -TextLine $case.TextLines[$i]
                    [void]$hl7Lines.Add($obxSegment)
                }
            }
        } else {
            # Standard facilities: include all OBX segments
            for ($i = 0; $i -lt $case.TextLines.Count; $i++) {
                $obxSegment = Build-OBXSegment -LineNumber ($i + 1) -TextLine $case.TextLines[$i]
                [void]$hl7Lines.Add($obxSegment)
            }
        }
    }
    
    # Write output file
    if ($OutputPath) {
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        $hl7Lines | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "HL7 file created: $OutputPath" -ForegroundColor Green
        Write-Host "Total cases processed: $($cases.Count)" -ForegroundColor Cyan
    }
    
    return @{
        Cases = $cases
        OutputPath = $OutputPath
        HL7Lines = $hl7Lines
    }
}
#endregion