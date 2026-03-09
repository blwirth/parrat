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

function Get-PatientLine {
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

function Get-SpecimenDate {
    param([string]$Line)

    if ($Line -match 'COLL:\s*(\d{2}/\d{2}/\d{2,4})') {
        return $matches[1]
    }
    return ''
}

function Get-PathReportID {
    param([string]$Line)

    if ($Line -match 'SPEC\s*[:#]\s*(?:.*?:)?(\S+)\s+COLL:') {
        return $matches[1]
    }
    return ''
}

function New-MSHSegment {
    param(
        [int]$CaseNumber,
        [string]$CLIA,
        [string]$TransmitDate = $script:UnknownDate
    )

    return "MSH|^~\&|E-Path Case=$CaseNumber|$CLIA|E-Path|NHSCR|$TransmitDate||ORU^R01^ORU_R01||P|2.5.1|||||USA||ENG||VOL_V_40_ORU_R01^NAACCR_CP"
}

function New-PIDSegment {
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

function New-OBRSegment {
    param(
        [string]$PathReportID,
        [string]$SpecimenDateHL7
    )

    # Removed the unknown physician--useless info--but will keep below comment for position reference if we want to parse it eventually
    # Original format: "OBR|1||$PathReportID||||$SpecimenDateHL7|||||||||^physicianNameLast^physicianNameFirst^physicianNameMiddle|||||||||F||||||||"
    return "OBR|1||$PathReportID||||$SpecimenDateHL7||||||||||||||||||F||||||||"
}

function New-OBXSegment {
    param(
        [int]$LineNumber,
        [string]$TextLine
    )

    return "OBX|$LineNumber|TX|||$TextLine"
}

#region SJH-Specific Helper Functions
#region SJH Parsing Helpers

function Get-SJHDateFromString {
    # Parse a date string like "1/1/2024" or "01/01/2024"
    param([string]$DateString)

    if ([string]::IsNullOrWhiteSpace($DateString)) { return $null }

    try {
        return [DateTime]::Parse($DateString)
    } catch {
        return $null
    }
}

function Get-SJHCaseLine {
    # Parse the case header line: NC24-1 Patient JOHN, DOE Age: 45 Sex: M COLL: 1/1/2024 ...
    # Based on original SAS regex patterns
    param([string]$Line)

    $result = @{
        PathReportID = ''
        NameLast = ''
        NameFirst = ''
        NameMiddle = ''
        Age = $null
        Sex = ''
        MRN = ''
        SpecimenDate = $null
    }

    # Path Report ID: (NH|NS|NC)23-123, (NH|NS|NC)24-1, etc.
    # Match pattern like SAS: /\b(NH|NS|NC)23-\d+/
    if ($Line -match '\b(NH|NS|NC)\d{2}-\d+') {
        $result.PathReportID = $matches[0]
    }

    # Patient name: SAS pattern with optional digits, hyphens/spaces in last name, proper lookahead
    # Pattern: /Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?(?=\s*(?:Age:|\d{4,7}\b|MD:|MRN:|$))/i
    if ($Line -match 'Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?(?=\s*(?:Age:|\d{4,7}\b|MD:|MRN:|$))') {
        $result.NameLast = $matches[1]
        $result.NameFirst = $matches[2]
        if ($matches[3]) {
            $result.NameMiddle = $matches[3]
        }
    }

    # Age: /Age:\s*(\d{1,3})\b/i
    if ($Line -match 'Age:\s*(\d{1,3})\b') {
        $result.Age = [int]$matches[1]
    }

    # Sex: /Sex:\s*([MF])\b/i
    if ($Line -match 'Sex:\s*([MF])\b') {
        $result.Sex = $matches[1]
    }

    # MRN: More complex pattern from SAS
    # /(?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))/i
    if ($Line -match '(?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))') {
        $result.MRN = $matches[1]
    }

    # Note: Specimen date is parsed from all lines in Get-SJHCases using date_re pattern
    # to find minimum date, matching SAS behavior

    return $result
}

function Get-SJHDOB {
    param(
        [object]$Age,
        [DateTime]$SpecimenDate
    )

    if ($Age -and $SpecimenDate) {
        $dobYear = $SpecimenDate.Year - [int]$Age
        if ($dobYear -ge 1800 -and $dobYear -le 2200) {
            return ('{0}9999' -f $dobYear.ToString('0000'))
        }
    }
    return $script:UnknownDate
}

function Format-SJHWhitespace {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return ([regex]::Replace($s.Trim(), '\s+', ' '))
}
#endregion

#endregion

#region Parsing Functions
function Get-StandardCases {
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
            $patientInfo = Get-PatientLine $line
            $currentCase.PatientData = $patientInfo
        }

        # Parse specimen date from any line containing it
        $specimenDate = Get-SpecimenDate $line
        if ($specimenDate) {
            $currentCase.SpecimenDate = $specimenDate
        }

        # Parse path report ID from any line containing it
        $pathReportID = Get-PathReportID $line
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

function Get-SJHCases {
    param([string]$InputPath)

    # Read input file
    $rawText = [System.IO.File]::ReadAllText($InputPath, [System.Text.Encoding]::Default)

    # Split to lines
    $lines = $rawText -split "\r?\n"

    # Skip line prefixes
    $skipPrefixes = @(
        'Tissue Committee Report',
        'Date/Time Printed:',
        'Selection Criteria:',
        'Part Type:'
    )

    # Case start pattern: SAS pattern /^\s*(?:NH|NS|NC)2[0-9]-\d+/
    # Allows optional whitespace, requires year to start with 2 (23, 24, 25, etc.)
    $caseStartRe = [regex]'^\s*(?:NH|NS|NC)2[0-9]-\d+'

    # Storage for parsed cases
    $cases = [System.Collections.ArrayList]::new()
    $caseNumber = 0
    $currentCase = $null

    foreach ($line0 in $lines) {
        $line = Format-SJHWhitespace $line0
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

        # Check for case boundary (line starts with path report ID)
        if ($caseStartRe.IsMatch($line)) {
            # Save previous case if exists
            if ($currentCase) {
                [void]$cases.Add($currentCase)
            }

            # Parse the case header line
            $caseInfo = Get-SJHCaseLine $line

            # Start new case
            $caseNumber++
            $currentCase = @{
                CaseNumber = $caseNumber
                PatientData = @{
                    NameLast = $caseInfo.NameLast
                    NameFirst = $caseInfo.NameFirst
                    NameMiddle = $caseInfo.NameMiddle
                    BirthDate = ''
                    Sex = $caseInfo.Sex
                    MedicalRecordNumber = $caseInfo.MRN
                }
                SpecimenDate = ''
                PathReportID = $caseInfo.PathReportID
                TextLines = [System.Collections.ArrayList]::new()
                Age = $caseInfo.Age
                SpecimenDateObj = $null
            }

            # Derive DOB from Age and SpecimenDate
            if ($currentCase.Age -and $currentCase.SpecimenDateObj) {
                $currentCase.PatientData.BirthDate = Get-SJHDOB -Age $currentCase.Age -SpecimenDate $currentCase.SpecimenDateObj
            }
        }

        if ($null -eq $currentCase) {
            continue
        }

        # Parse fields from any line (SAS pattern - fields can appear on any line in the case)
        # Update name if found
        if ($line -match 'Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?(?=\s*(?:Age:|\d{4,7}\b|MD:|MRN:|$))') {
            if (-not $currentCase.PatientData.NameLast) { $currentCase.PatientData.NameLast = $matches[1] }
            if (-not $currentCase.PatientData.NameFirst) { $currentCase.PatientData.NameFirst = $matches[2] }
            if ($matches[3] -and -not $currentCase.PatientData.NameMiddle) { $currentCase.PatientData.NameMiddle = $matches[3] }
        }

        # Update age if found
        if ($line -match 'Age:\s*(\d{1,3})\b') {
            if (-not $currentCase.Age) {
                $currentCase.Age = [int]$matches[1]
            }
        }

        # Update sex if found
        if ($line -match 'Sex:\s*([MF])\b') {
            if (-not $currentCase.PatientData.Sex) {
                $currentCase.PatientData.Sex = $matches[1]
            }
        }

        # Update MRN if found
        if ($line -match '(?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))') {
            if (-not $currentCase.PatientData.MedicalRecordNumber) {
                $currentCase.PatientData.MedicalRecordNumber = $matches[1]
            }
        }

        # Update path report ID if found
        if ($line -match '\b(NH|NS|NC)\d{2}-\d+') {
            if (-not $currentCase.PathReportID) {
                $currentCase.PathReportID = $matches[0]
            }
        }

        # Parse dates from line (SAS pattern: find all dates, take minimum)
        # Pattern: /\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b/
        $dateRe = [regex]'\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b'
        $dateMatches = $dateRe.Matches($line)
        if ($dateMatches.Count -gt 0) {
            $dates = foreach ($m in $dateMatches) {
                $dt = Get-SJHDateFromString $m.Groups[1].Value
                if ($dt) { $dt }
            }
            if ($dates) {
                $minDate = ($dates | Sort-Object | Select-Object -First 1)
                # Update specimen date if this is earlier or if we don't have one yet
                if (-not $currentCase.SpecimenDateObj -or $minDate -lt $currentCase.SpecimenDateObj) {
                    $currentCase.SpecimenDateObj = $minDate
                    $currentCase.SpecimenDate = $minDate.ToString('MM/dd/yyyy')
                    # Recalculate DOB if we have age
                    if ($currentCase.Age -and $currentCase.SpecimenDateObj) {
                        $currentCase.PatientData.BirthDate = Get-SJHDOB -Age $currentCase.Age -SpecimenDate $currentCase.SpecimenDateObj
                    }
                }
            }
        }

        # Add line to text
        [void]$currentCase.TextLines.Add($line)
    }

    # Save final case
    if ($currentCase) {
        [void]$cases.Add($currentCase)
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

    if (-not (Test-Path $InputPath)) {
        throw "Input file not found: $InputPath"
    }

    $facilityConfig = $script:FacilityConfig[$FacilityName]
    if (-not $facilityConfig) {
        throw "Unknown facility: $FacilityName"
    }

    # Storage for parsed cases
    $cases = [System.Collections.ArrayList]::new()

    if ($FacilityName -eq 'SJH') {
        $cases = Get-SJHCases -InputPath $InputPath
    } else {
        $cases = Get-StandardCases -InputPath $InputPath -FacilityName $FacilityName
    }

    # Preview mode - return parsed data
    if ($PreviewOnly) {
        return @{
            Cases = $cases
            FacilityConfig = $facilityConfig
            InputPath = $InputPath
        }
    }

    $hl7Lines = [System.Collections.ArrayList]::new()

    foreach ($case in $cases) {
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

        $mshSegment = New-MSHSegment -CaseNumber $case.CaseNumber -CLIA $facilityConfig.CLIA
        $pidSegment = New-PIDSegment -PatientData $case.PatientData -BirthDateHL7 $birthDateHL7
        $obrSegment = New-OBRSegment -PathReportID $case.PathReportID -SpecimenDateHL7 $specimenDateHL7

        [void]$hl7Lines.Add($mshSegment)
        [void]$hl7Lines.Add($pidSegment)
        [void]$hl7Lines.Add($obrSegment)

        # Was previously removing obx 1 but some pathology reports convert to text
        # non-uniformly and obx 1 then contains final dx info)
        for ($i = 0; $i -lt $case.TextLines.Count; $i++) {
            $obxSegment = New-OBXSegment -LineNumber ($i + 1) -TextLine $case.TextLines[$i]
            [void]$hl7Lines.Add($obxSegment)
        }
    }

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