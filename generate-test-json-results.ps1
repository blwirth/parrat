# This script generates fake JSON files for testing purposes.
# It can be run from the command line with the -OutputPath parameter.
# If no parameter is specified, it will use the script's directory for the output path.
# .\generate-test-json-results.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PSScriptRoot"
)

# Ensure folder exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath
    Write-Host "Created directory: $OutputPath"
}

# Function to generate fake JSON files
function New-FakeJSON {
    param ($fileName)

    # Define fake JSON structure
    $fakeJson = @{
        MessageID     = "N:\eMaRC_lite\source\facility\2025_02_Mon\FakeFile.hl71"
        Reportable    = $false
        DiagnosisDate = "20250225"
        Entities      = @(
            @{
                Id                 = Get-Random -Minimum 100000 -Maximum 999999
                EntityType         = 0
                OBXSegment         = 1
                EntityPhrase       = "malignant neoplasm"
                Offset             = Get-Random -Minimum 200 -Maximum 1000
                Length             = 20
                IsNonreportableSkinHistology = $false
                IsSkinSite         = $false
                IsNegated          = $true
                NegationType       = 1
                NegationPhrase     = "no evidence of"
                Code               = "8000"
                AdditionalCode     = "3"
                SiteCriteria       = "exclude C44"
                IsNonReportableTerm= $false
                ConditionalPhrase  = ""
            }
        )
        CodedResult   = @{
            Histology  = ""
            Site       = ""
            Behavior   = ""
            Laterality = ""
            IsSkinCase = $false
        }
        OBXTexts      = @{
            FinalDiagnosis  = "Malignant neoplasm detected."
            TextDiagnosis   = "Final report."
        }
    }

    # Convert to JSON format and save
    $fakeJson | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath\$fileName"
}

# Generate multiple test files
for ($i=1; $i -le 10; $i++) {
    $messageNum = Get-Random -Minimum 1 -Maximum 9999
    New-FakeJSON -fileName "originalfile_${messageNum}_result.json"
}

Write-Host "Fake JSON test files generated in $OutputPath"
