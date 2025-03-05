# .\read-json-results-3.ps1 -InputPath "N:\eMaRC_lite\reports\SNH\2025_02_Feb" -OutputPath "N:\eMaRC_lite\reports\SNH\2025_02_Feb\output"

# Define script parameters
param(
    [Parameter(Mandatory=$false)]
    [string]$InputPath = "$PSScriptRoot",

    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)

# Ensure OutputPath is a folder
if (-not $OutputPath) {
    $OutputPath = $InputPath
}

# Ensure the output directory exists
if (!(Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Define output CSV paths
$SummaryCSV  = Join-Path $OutputPath "SummaryReport.csv"
$EntityCSV   = Join-Path $OutputPath "EntitySummary.csv"
$MessagesCSV = Join-Path $OutputPath "MessagesSummary.csv"

# Initialize tracking dictionaries (MUST be outside loop to persist across files)
$entityCounts = @{}
$entityMap = @{}   # Stores unique entity definitions mapped to a single CustomId
$totalMessages = 0
$totalReportableMessages = 0
$totalNonReportableMessages = 0

# Function to extract EntityType: 0 from JSON files
function Get-EntityTypeZeroData {
    param ($filePath)

    try {
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $jsonContent.PSObject.Properties["Entities"]) { return $null }

        # Extract reportability from the JSON file
        $reportableStatus = if ($jsonContent.PSObject.Properties["Reportable"]) { $jsonContent.Reportable } else { $false }

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

    # Initialize CSV headers
    "Category,Count" | Out-File -FilePath $SummaryCSV -Encoding UTF8
    "EntityId,CustomId,EntityPhrase,IsNegated,NegationType,NegationPhrase,Code,AdditionalCode,IsNonreportableSkinHistology,IsSkinSite,IsNonReportableTerm,SiteCriteria,Count" | Out-File -FilePath $EntityCSV -Encoding UTF8
    "FileName,Reportable,MessageNumber,CustomEntityIds" | Out-File -FilePath $MessagesCSV -Encoding UTF8

    foreach ($file in $jsonFiles) {
        Write-Host "`nProcessing file: $($file.Name)"
        $fileData = Get-EntityTypeZeroData -filePath $file.FullName
        $totalMessages++

        if (!$fileData) { continue }  # We no longer skip reports

        $fileResults = $fileData.Entities
        $reportableStatus = if ($fileData.Reportable) { "Yes" } else { "No" }
        $messageNumber = $fileData.MessageNumber

        # Track reportable & non-reportable counts
        if ($fileData.Reportable) {
            $totalReportableMessages++
        } else {
            $totalNonReportableMessages++
        }

        # Store all CustomIds for this message
        $customEntityIds = @()

        foreach ($record in $fileResults) {
            # Generate a unique key based on all defining attributes
            $entityKey = "$($record.Id)-$($record.EntityPhrase)-$($record.IsNegated)-$($record.NegationType)-$($record.NegationPhrase)-$($record.Code)-$($record.AdditionalCode)-$($record.IsNonreportableSkinHistology)-$($record.IsSkinSite)-$($record.IsNonReportableTerm)-$($record.SiteCriteria)"

            # Check if the entity already exists in the dictionary
            if ($entityMap.ContainsKey($entityKey)) {
                $customId = $entityMap[$entityKey]  # Reuse the existing CustomId
            } else {
                # Generate a new CustomId and store it
                $customId = "E" + [math]::Abs($entityKey.GetHashCode())
                $entityMap[$entityKey] = $customId  # Save this ID for future occurrences
            }

            # Add to list of entity IDs for this message
            $customEntityIds += $customId

            # Store entity details in the summary
            if (-not $entityCounts.ContainsKey($entityKey)) {
                $entityCounts[$entityKey] = @{
                    EntityId = $record.Id
                    CustomId = $customId
                    EntityPhrase = $record.EntityPhrase
                    IsNegated = $record.IsNegated
                    NegationType = $record.NegationType
                    NegationPhrase = $record.NegationPhrase
                    Code = $record.Code
                    AdditionalCode = $record.AdditionalCode
                    IsNonreportableSkinHistology = $record.IsNonReportableSkinHistology
                    IsSkinSite = $record.IsSkinSite
                    IsNonReportableTerm = $record.IsNonReportableTerm
                    SiteCriteria = $record.SiteCriteria
                    Count = 1
                }
            } else {
                $entityCounts[$entityKey].Count++
            }
        }

        # Save Messages Summary (using custom entity IDs)
        "$($fileData.FileName),$reportableStatus,$messageNumber,$($customEntityIds -join ', ')" | Out-File -FilePath $MessagesCSV -Append -Encoding UTF8
    }

    # Save Entity Summary
    foreach ($entity in $entityCounts.Values) {
        # Ensure EntityPhrase is enclosed in double quotes to handle commas
        $entityPhrase = '"' + $entity.EntityPhrase + '"'

        "$($entity.EntityId),$($entity.CustomId),$entityPhrase,$($entity.IsNegated),$($entity.NegationType),$($entity.NegationPhrase),$($entity.Code),$($entity.AdditionalCode),$($entity.IsNonreportableSkinHistology),$($entity.IsSkinSite),$($entity.IsNonReportableTerm),$($entity.SiteCriteria),$($entity.Count)" | Out-File -FilePath $EntityCSV -Append -Encoding UTF8
    }

    # Save Summary Report
    "Total Messages Processed,$totalMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8
    "Total Reportable Messages,$totalReportableMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8
    "Total Non-Reportable Messages,$totalNonReportableMessages" | Out-File -FilePath $SummaryCSV -Append -Encoding UTF8

    Write-Host "`nProcessing Complete!"
}

# Execute script
Get-Folder -folderPath $InputPath -outputPath $OutputPath
