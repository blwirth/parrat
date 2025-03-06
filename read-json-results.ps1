# .\read-json-results.ps1 -InputPath "N:\eMaRC_lite\reports\SNH\Archive\2025_02_Feb" -OutputPath "N:\eMaRC_lite\reports\SNH\Archive\2025_02_Feb\output" -FacilityName "SNH" -FacilityId "6120290" -Year "2025" -Month "02"

# Define script parameters
param(
    [Parameter(Mandatory=$false)]
    [string]$InputPath = "$PSScriptRoot",

    [Parameter(Mandatory=$false)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [string]$FacilityName,

    [Parameter(Mandatory=$false)]
    [string]$FacilityId,

    [Parameter(Mandatory=$true)]
    [ValidateRange(2023, 2025)]
    [int]$Year,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1, 12)]
    [int]$Month
)

# Define a log file and a function to write logs for debugging
$LogFile = Join-Path $OutputPath "script_log.txt"

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Validate input parameters before running
if (-not $InputPath -or -not (Test-Path $InputPath)) {
    Write-Log "ERROR: InputPath is missing or invalid: $InputPath" "ERROR"
    exit 1
}
if (-not $OutputPath) {
    Write-Log "ERROR: OutputPath is missing." "ERROR"
    exit 1
}
if ($Year -notmatch '^\d{4}$' -or $Year -lt 2023 -or $Year -gt 2025) {
    Write-Log "ERROR: Invalid year: $Year" "ERROR"
    exit 1
}
if ($Month -notmatch '^(0[1-9]|1[0-2])$') {
    Write-Log "ERROR: Invalid month: $Month" "ERROR"
    exit 1
}

# Ensure facility_id is a 7-digit number (default to 9999999 if missing)
if (-not $FacilityId -or $FacilityId -notmatch '^\d{7}$') {
    Write-Log "WARNING: Facility ID is missing or invalid. Defaulting to 9999999." "WARNING"
    $FacilityId = "9999999"
}

# Ensure the output directory exists
if (!(Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Log "Created output directory: $OutputPath"
}

# Define CSV paths
$FacilitiesCSV = Join-Path $PSScriptRoot "facilities.csv"
$EntityCountsCSV = Join-Path $PSScriptRoot "entity_counts.csv"
$SummaryCSV = Join-Path $PSScriptRoot "summary_reports.csv"
$EntityMasterCSV = Join-Path $PSScriptRoot "entity_master.csv"
$MessagesCSV = Join-Path $OutputPath "$FacilityId`_$Year`_$Month`_messages.csv"
$MessageEntitiesCSV = Join-Path $OutputPath "$FacilityId`_$Year`_$Month`_message_entities.csv"

# Ensure CSV files exist and create headers if missing
$CsvHeaders = @{
    $FacilitiesCSV     = "facility_id,facility_name"
    $EntityMasterCSV   = "custom_id,entity_id,entity_phrase,is_negated,negation_type,negation_phrase,code,additional_code,is_nonreportable_skin_histology,is_skin_site,is_nonreportable_term,site_criteria"
    $EntityCountsCSV   = "facility_id,year,month,custom_id,count"
    $MessagesCSV       = "message_id,facility_id,year,month,reportable"
    $MessageEntitiesCSV = "message_id,custom_id,entity_count"
    $SummaryCSV        = "facility_id,year,month,category,count"
}

foreach ($file in $CsvHeaders.Keys) {
    if (!(Test-Path $file)) {
        $CsvHeaders[$file] | Set-Content -Path $file -Encoding UTF8
        Write-Log "Created missing file: $file"
    }
}

# Ensure facilities.csv has no duplicate entries
if (!(Select-String -Path $FacilitiesCSV -Pattern "^$FacilityId,")) {
    "$FacilityId,$FacilityName" | Out-File -FilePath $FacilitiesCSV -Append -Encoding UTF8
} else {
    Write-Log "Skipping duplicate facility: $FacilityId"
}

# Load entity_master dictionary to avoid duplicate entity insertions
$EntityMasterDict = @{}
if (Test-Path $EntityMasterCSV) {
    Import-Csv $EntityMasterCSV | ForEach-Object {
        $entityKey = "$($_.entity_id)-$($_.entity_phrase)-$($_.is_negated)-$($_.negation_type)-$($_.negation_phrase)-$($_.code)-$($_.additional_code)-$($_.is_nonreportable_skin_histology)-$($_.is_skin_site)-$($_.is_nonreportable_term)-$($_.site_criteria)"
        $EntityMasterDict[$entityKey] = $_.custom_id
    }
}

# Process JSON files
function Get-Folder {
    param ($folderPath)

    $jsonFiles = Get-ChildItem -Path $folderPath -Filter "*.json" | Where-Object { $_.Name -match '_\d+_result\.json$' }
    Write-Log "Found $($jsonFiles.Count) files to process."

    # Initialize counters
    $entityCounts = @{}
    $totalMessages = 0
    $reportableMessages = 0
    $nonReportableMessages = 0

    foreach ($file in $jsonFiles) {
        $fileData = Get-EntityTypeZeroData -filePath $file.FullName
        if (!$fileData) { continue }
        
        $totalMessages++
        if ($fileData.Reportable -eq "Yes") {
            $reportableMessages++
        } else {
            $nonReportableMessages++
        }

        "$($fileData.MessageID),$FacilityId,$Year,$Month,$($fileData.Reportable)" | Out-File -FilePath $MessagesCSV -Append -Encoding UTF8

        # Dictionary to track entity occurrences within this message
        $messageEntityCounts = @{}

        foreach ($record in $fileData.Entities) {
            # Safely get properties with defaults if missing
            $entityProperties = @{
                Id = if ($record.PSObject.Properties["Id"]) { $record.Id } else { "" }
                EntityPhrase = if ($record.PSObject.Properties["EntityPhrase"]) { $record.EntityPhrase } else { "" }
                IsNegated = if ($record.PSObject.Properties["IsNegated"]) { $record.IsNegated } else { $false }
                NegationType = if ($record.PSObject.Properties["NegationType"]) { $record.NegationType } else { "" }
                NegationPhrase = if ($record.PSObject.Properties["NegationPhrase"]) { $record.NegationPhrase } else { "" }
                Code = if ($record.PSObject.Properties["Code"]) { $record.Code } else { "" }
                AdditionalCode = if ($record.PSObject.Properties["AdditionalCode"]) { $record.AdditionalCode } else { "" }
                IsNonreportableSkinHistology = if ($record.PSObject.Properties["IsNonreportableSkinHistology"]) { $record.IsNonreportableSkinHistology } else { $false }
                IsSkinSite = if ($record.PSObject.Properties["IsSkinSite"]) { $record.IsSkinSite } else { $false }
                IsNonReportableTerm = if ($record.PSObject.Properties["IsNonReportableTerm"]) { $record.IsNonReportableTerm } else { $false }
                SiteCriteria = if ($record.PSObject.Properties["SiteCriteria"]) { $record.SiteCriteria } else { "" }
            }

            $entityKey = "$($entityProperties.Id)-$($entityProperties.EntityPhrase)-$($entityProperties.IsNegated)-$($entityProperties.NegationType)-$($entityProperties.NegationPhrase)-$($entityProperties.Code)-$($entityProperties.AdditionalCode)-$($entityProperties.IsNonreportableSkinHistology)-$($entityProperties.IsSkinSite)-$($entityProperties.IsNonReportableTerm)-$($entityProperties.SiteCriteria)"

            # Get or create custom_id
            if (!$EntityMasterDict.ContainsKey($entityKey)) {
                $custom_id = "E" + [math]::Abs($entityKey.GetHashCode())
                $EntityMasterDict[$entityKey] = $custom_id
                
                # Write complete entity record to master
                "$custom_id,$($entityProperties.Id),$($entityProperties.EntityPhrase),$($entityProperties.IsNegated),$($entityProperties.NegationType),$($entityProperties.NegationPhrase),$($entityProperties.Code),$($entityProperties.AdditionalCode),$($entityProperties.IsNonreportableSkinHistology),$($entityProperties.IsSkinSite),$($entityProperties.IsNonReportableTerm),$($entityProperties.SiteCriteria)" | 
                    Out-File -FilePath $EntityMasterCSV -Append -Encoding UTF8
            }
            $custom_id = $EntityMasterDict[$entityKey]
            
            # Track entity count
            $countKey = "$FacilityId,$Year,$Month,$custom_id"
            $entityCounts[$countKey] = ($entityCounts[$countKey] + 1)
            
            # Track entity occurrences within this message
            $messageEntityKey = "$($fileData.MessageID)-$custom_id"
            $messageEntityCounts[$messageEntityKey] = ($messageEntityCounts[$messageEntityKey] + 1)
        }

        # Write message-entity relationships with counts
        foreach ($key in $messageEntityCounts.Keys) {
            $messageId, $customId = $key -split '-'
            "$messageId,$customId,$($messageEntityCounts[$key])" | Out-File -FilePath $MessageEntitiesCSV -Append -Encoding UTF8
        }
    }

    # Write entity counts to CSV
    foreach ($countKey in $entityCounts.Keys) {
        "$countKey,$($entityCounts[$countKey])" | Out-File -FilePath $EntityCountsCSV -Append -Encoding UTF8
    }

    # Write summary statistics
    "$FacilityId,$Year,$Month,Total Messages,$totalMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8
    "$FacilityId,$Year,$Month,Reportable Messages,$reportableMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8
    "$FacilityId,$Year,$Month,Non-Reportable Messages,$nonReportableMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8

    Write-Log "Processing complete. Total messages: $totalMessages, Reportable: $reportableMessages, Non-Reportable: $nonReportableMessages"
}

# Function to extract EntityType: 0 from JSON files
function Get-EntityTypeZeroData {
    param ($filePath)

    try {
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json -ErrorAction Stop
        
        # Every record should have these properties
        if (-not $jsonContent.PSObject.Properties["Entities"] -or -not $jsonContent.PSObject.Properties["Reportable"]) {
            Write-Log "Skipping file: $filePath (Missing required properties)" "WARNING"
            return $null
        }

        $reportableStatus = if ([bool]$jsonContent.Reportable) { "Yes" } else { "No" }
        $entities = $jsonContent.Entities | Where-Object { $_.EntityType -eq 0 }
        $fileName = (Get-Item $filePath).Name
        
        return @{
            Entities = $entities
            Reportable = $reportableStatus
            MessageID = $fileName
        }
    } catch {
        Write-Log "Error processing file: $filePath" "ERROR"
        return $null
    }
}

# Execute script
Get-Folder -folderPath $InputPath
