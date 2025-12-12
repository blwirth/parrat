# convert-excel-to-json.ps1
# One-time script to convert Excel files to fast-loading JSON format
# Run this once to generate JSON files, then the script will automatically use them

param(
    [string]$ScriptDir = $PSScriptRoot
)

# Load the Excel reading functions
. "$ScriptDir\assign-site-laterality.ps1"

$topoXlsx = Join-Path $ScriptDir "Topography.xlsx"
$melTopoXlsx = Join-Path $ScriptDir "TopographyMelanoma.xlsx"
$latXlsx = Join-Path $ScriptDir "Laterality.xlsx"

$topoJson = Join-Path $ScriptDir "Topography.jsonl"
$melTopoJson = Join-Path $ScriptDir "TopographyMelanoma.jsonl"
$latJson = Join-Path $ScriptDir "Laterality.json"

# Check if Excel files exist
if (-not (Test-Path $topoXlsx)) {
    Write-Error "Missing Topography.xlsx in script folder: $ScriptDir"
    exit 1
}
if (-not (Test-Path $melTopoXlsx)) {
    Write-Error "Missing TopographyMelanoma.xlsx in script folder: $ScriptDir"
    exit 1
}
if (-not (Test-Path $latXlsx)) {
    Write-Error "Missing Laterality.xlsx in script folder: $ScriptDir"
    exit 1
}

# Convert Topography
$topoMap = Read-TopographyExcel $topoXlsx | Where-Object { $_.Code -and $_.SearchPhrase -and $_.Code -notlike 'C77?' }
$topoLines = $topoMap | ForEach-Object { 
    $_ | ConvertTo-Json -Compress 
}
$topoLines | Set-Content $topoJson -Encoding UTF8

# Convert Melanoma Topography
$melTopoMap = Read-TopographyExcel $melTopoXlsx | Where-Object { $_.Code -and $_.SearchPhrase }
$melTopoLines = $melTopoMap | ForEach-Object { 
    $_ | ConvertTo-Json -Compress 
}
$melTopoLines | Set-Content $melTopoJson -Encoding UTF8

# Convert Laterality (array format)
$latCodes = Read-LateralityExcel $latXlsx
$latArray = $latCodes.Keys | Sort-Object
$latArray | ConvertTo-Json | Set-Content $latJson -Encoding UTF8

Write-Host "JSON files created:" -ForegroundColor Green
Write-Host "  - $topoJson" -ForegroundColor Cyan
Write-Host "  - $melTopoJson" -ForegroundColor Cyan
Write-Host "  - $latJson" -ForegroundColor Cyan

