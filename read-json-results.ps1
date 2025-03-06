# .\read-json-results.ps1 -InputPath "N:\eMaRC_lite\reports\SNH\Archive\2025_02_Feb" -OutputPath "N:\eMaRC_lite\reports\SNH\Archive\2025_02_Feb\output" -Facility "SNH" -FacilityNumber "6120290" -Year "2025" -Month "02"

# Define script parameters
param(
    [Parameter(Mandatory=$false)]
    [string]$InputPath = "$PSScriptRoot",

    [Parameter(Mandatory=$false)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [string]$Facility,

    [Parameter(Mandatory=$false)]
    [string]$FacilityNumber,

    [Parameter(Mandatory=$true)]
    [string]$Year,

    [Parameter(Mandatory=$true)]
    [string]$Month
)

# Ensure FacilityNumber is a 7-digit number (default to 9999999 if missing)
if (-not $FacilityNumber -or $FacilityNumber -notmatch '^\d{7}$') {
    Write-Host "Warning: Facility Number is missing or invalid. Defaulting to 9999999." -ForegroundColor Yellow
    $FacilityNumber = "9999999"
}

# Ensure the output directory exists
if (!(Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Define centralized CSV paths (persist across all runs)
$FacilitiesCSV = Join-Path $PSScriptRoot "Facilities.csv"
$EntityCountsCSV = Join-Path $PSScriptRoot "EntityCounts.csv"
$SummaryCSV = Join-Path $PSScriptRoot "SummaryReport.csv"
$EntityMasterCSV = Join-Path $PSScriptRoot "EntityMaster.csv"

# Define MessagesSummary.csv (local, per-run file)
$MessagesCSV = Join-Path $OutputPath "$Facility_$Year_$Month_MessagesSummary.csv"

# Initialize tracking dictionaries
$EntityMasterDict = @{}
$totalMessages = 0
$totalReportableMessages = 0
$totalNonReportableMessages = 0

# Ensure Facilities.csv exists and update if necessary
if (!(Test-Path $FacilitiesCSV)) {
    "FacilityNumber,FacilityName" | Set-Content -Path $FacilitiesCSV -Encoding UTF8
}

# Check if this facility is already recorded
$existingFacilities = Import-Csv $FacilitiesCSV | Select-Object -ExpandProperty FacilityNumber
if ($FacilityNumber -notin $existingFacilities) {
    "$FacilityNumber,$Facility" | Out-File -FilePath $FacilitiesCSV -Append -Encoding UTF8
}

# Ensure EntityMaster.csv exists
if (Test-Path $EntityMasterCSV) {
    Import-Csv $EntityMasterCSV | ForEach-Object {
        $entityKey = "$($_.EntityId)-$($_.EntityPhrase)-$($_.IsNegated)-$($_.NegationType)-$($_.NegationPhrase)-$($_.Code)-$($_.AdditionalCode)-$($_.IsNonreportableSkinHistology)-$($_.IsSkinSite)-$($_.IsNonReportableTerm)-$($_.SiteCriteria)"
        $EntityMasterDict[$entityKey] = $_.CustomId
    }
} else {
    "EntityId,CustomId,EntityPhrase,IsNegated,NegationType,NegationPhrase,Code,AdditionalCode,IsNonreportableSkinHistology,IsSkinSite,IsNonReportableTerm,SiteCriteria" | Set-Content -Path $EntityMasterCSV -Encoding UTF8
}

# Function to extract EntityType: 0 from JSON files
function Get-EntityTypeZeroData {
    param ($filePath)

    try {
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $jsonContent.PSObject.Properties["Entities"]) { return $null }

        # Extract reportability from the JSON file
		$reportableStatus = if ($jsonContent.PSObject.Properties["Reportable"] -and [bool]$jsonContent.Reportable) { "Yes" } else { "No" }

        $entities = $jsonContent.Entities | Where-Object { $_.EntityType -eq 0 }
        # Extract the message number from the filename
        $fileName = (Get-Item $filePath).Name
        $messageNumber = if ($fileName -match '_(\d+)_result\.json$') { $matches[1] } else { "Unknown" }

        return @{
            Entities = $entities
            Reportable = $reportableStatus
            FileName = $fileName
            MessageNumber = $messageNumber
        }
    } catch {
        Write-Host "Error processing file: $filePath" -ForegroundColor Red
        return $null
    }
}

# Function to process JSON files
function Get-Folder {
    param ($folderPath)

    $jsonFiles = Get-ChildItem -Path $folderPath -Filter "*.json" | Where-Object { $_.Name -match '_\d+_result\.json$' }
    Write-Host "Found $($jsonFiles.Count) files matching the pattern *_[number]_result.json"

    # Ensure CSV headers exist
    if (!(Test-Path $EntityCountsCSV)) {
        "FacilityNumber,Year,Month,CustomId,Count" | Set-Content -Path $EntityCountsCSV -Encoding UTF8
    }
    if (!(Test-Path $SummaryCSV)) {
        "FacilityNumber,Year,Month,Category,Count" | Set-Content -Path $SummaryCSV -Encoding UTF8
    }
    if (!(Test-Path $MessagesCSV)) {
        "FileName,Reportable,MessageNumber,CustomEntityIds" | Set-Content -Path $MessagesCSV -Encoding UTF8
    }

    $facilityEntityCounts = @{}

    foreach ($file in $jsonFiles) {
        Write-Host "nProcessing file: $($file.Name)"
        $fileData = Get-EntityTypeZeroData -filePath $file.FullName
        $totalMessages++

        if (!$fileData) { continue }

        if ($fileData.Reportable) {
            $totalReportableMessages++
        } else {
            $totalNonReportableMessages++
        }

        $customEntityIds = @()

        foreach ($record in $fileData.Entities) {
            $entityKey = "$($record.Id)-$($record.EntityPhrase)-$($record.IsNegated)-$($record.NegationType)-$($record.NegationPhrase)-$($record.Code)-$($record.AdditionalCode)-$($record.IsNonreportableSkinHistology)-$($record.IsSkinSite)-$($record.IsNonReportableTerm)-$($record.SiteCriteria)"

            if ($EntityMasterDict.ContainsKey($entityKey)) {
                $customId = $EntityMasterDict[$entityKey]
            } else {
                $customId = "E" + [math]::Abs($entityKey.GetHashCode())
                $EntityMasterDict[$entityKey] = $customId
                "$($record.Id),$customId,""$($record.EntityPhrase)"",$($record.IsNegated),$($record.NegationType),$($record.NegationPhrase),$($record.Code),$($record.AdditionalCode),$($record.IsNonreportableSkinHistology),$($record.IsSkinSite),$($record.IsNonReportableTerm),$($record.SiteCriteria)" | Out-File -FilePath $EntityMasterCSV -Append -Encoding UTF8
            }

            $customEntityIds += $customId
            $facilityEntityCounts[$customId] = ($facilityEntityCounts[$customId] + 1)
        }

		"$($fileData.FileName),$($fileData.Reportable),$($fileData.MessageNumber),$($customEntityIds -join ', ')" | Out-File -FilePath $MessagesCSV -Append -Encoding UTF8
    }

    foreach ($customId in $facilityEntityCounts.Keys) {
        "$FacilityNumber,$Year,$Month,$customId,$($facilityEntityCounts[$customId])" | Out-File -FilePath $EntityCountsCSV -Append -Encoding UTF8
    }

    "$FacilityNumber,$Year,$Month,Total Messages Processed,$totalMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8
}

# Execute script
Get-Folder -folderPath $InputPath
