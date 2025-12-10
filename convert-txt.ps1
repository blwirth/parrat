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
        Name of facility (Parkland, Portsmouth, or Frisbie)
    
    .PARAMETER PreviewOnly
        If specified, returns parsed data without writing output file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Parkland', 'Portsmouth', 'Frisbie')]
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
        $birthDateHL7 = Convert-DateToHL7 $case.PatientData.BirthDate
        $specimenDateHL7 = Convert-DateToHL7 $case.SpecimenDate
        
        # Build segments (using different variable names to avoid $PID conflict)
        $mshSegment = Build-MSHSegment -CaseNumber $case.CaseNumber -CLIA $facilityConfig.CLIA
        $pidSegment = Build-PIDSegment -PatientData $case.PatientData -BirthDateHL7 $birthDateHL7
        $obrSegment = Build-OBRSegment -PathReportID $case.PathReportID -SpecimenDateHL7 $specimenDateHL7
        
        [void]$hl7Lines.Add($mshSegment)
        [void]$hl7Lines.Add($pidSegment)
        [void]$hl7Lines.Add($obrSegment)
        
        # Add all text lines as OBX segments
        for ($i = 0; $i -lt $case.TextLines.Count; $i++) {
            $obxSegment = Build-OBXSegment -LineNumber ($i + 1) -TextLine $case.TextLines[$i]
            [void]$hl7Lines.Add($obxSegment)
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