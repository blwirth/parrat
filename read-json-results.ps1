# This script reads JSON files from a folder and extracts EntityType: 0 records, then saves the results to a CSV file.
# It can be run from the command line with the -InputPath and -OutputPath parameters.
# If no parameters are specified, it will use the script's directory for the input path and create an output path with a timestamp in the input folder.
# .\read-json-results.ps1

param(
    [Parameter(Mandatory=$false)]
    # Default input path is the script's directory
    [string]$InputPath = "$PSScriptRoot",

    [Parameter(Mandatory=$false)]
    # If not specified, output path will be "[script directory]\FilteredReport_[timestamp].csv"
    [string]$OutputPath
)

# If no output path specified, create one with timestamp in the input folder
if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $InputPath "FilteredReport_$timestamp.csv"
}

# Function to extract EntityType: 0 from JSON files
function Get-EntityTypeZeroData {
    param ($filePath)

    try {
        # Read JSON content
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json -ErrorAction Stop

        # Ensure Entities exist (some messages don't have entities)
        if (-not $jsonContent.PSObject.Properties["Entities"] -or !$jsonContent.Entities) {
            Write-Host "Skipping file due to missing 'Entities': $filePath" -ForegroundColor Yellow
            return $null
        }

        # Extract EntityType: 0 records
        $entities = $jsonContent.Entities | Where-Object { $_.EntityType -eq 0 }

        if (!$entities) { return $null }  # Skip if no matching entities

        # Return structured results
        return $entities | ForEach-Object {
            [PSCustomObject]@{
                FileName         = (Get-Item $filePath).Name
                EntityPhrase     = $_.EntityPhrase
                IsNegated        = $_.IsNegated
                NegationType     = $_.NegationType
                NegationPhrase   = $_.NegationPhrase
                Code             = $_.Code
                AdditionalCode   = $_.AdditionalCode
                IsNonReportable  = $_.IsNonReportableTerm
                ConditionalPhrase= $_.ConditionalPhrase
            }
        }
    } catch {
        Write-Host "Error processing file: $filePath" -ForegroundColor Red
        Write-Host "Error Message: $_" -ForegroundColor Red
        return $null
    }
}

# Function to process all JSON files in the folder
function Get-Folder {
    param ($folderPath, $outputPath)

    # Get JSON files matching the naming pattern
    $jsonFiles = Get-ChildItem -Path $folderPath -Filter "*.json" | 
                Where-Object { $_.Name -match '_\d+_result\.json$' }

    Write-Host "Found $($jsonFiles.Count) files matching the pattern *_[number]_result.json"

    # Initialize CSV with headers
    "FileName,EntityPhrase,IsNegated,NegationType,NegationPhrase,Code,AdditionalCode,IsNonReportable,ConditionalPhrase" | Out-File -FilePath $outputPath -Encoding UTF8

    # Initialize tracking variables
    $totalFiles = 0
    $filesWithEntities = 0
    $negationType1Count = 0

    # Process each file
    foreach ($file in $jsonFiles) {
        $totalFiles++
        Write-Host "`nProcessing file: $($file.Name)"

        $fileResults = Get-EntityTypeZeroData -filePath $file.FullName

        if ($fileResults) {
            $filesWithEntities++
            $negationType1Count += ($fileResults | Where-Object { $_.NegationType -eq 1 }).Count
            $fileResults | Export-Csv -Path $outputPath -Append -NoTypeInformation -Encoding UTF8
            Write-Host "Found $(($fileResults | Measure-Object).Count) EntityType 0 records"
        } else {
            Write-Host "No EntityType 0 records found in this file"
        }
    }

    # Display summary
    Write-Host "`nProcessing Summary:"
    Write-Host "Total Files Processed: $totalFiles"
    Write-Host "Files with EntityType 0: $filesWithEntities"
    Write-Host "Entities with NegationType 1: $negationType1Count"
    Write-Host "Results saved to: $outputPath"
}

# Execute script
Get-Folder -folderPath $InputPath -outputPath $OutputPath
