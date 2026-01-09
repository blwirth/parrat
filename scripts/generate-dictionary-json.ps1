# generate-dictionary-json.ps1
# Parse the XML dictionary and create a compact JSON file

$xmlPath = Join-Path $PSScriptRoot "..\data\dictionaries\naaccr-data-dictionary-v25.xml"
$jsonPath = Join-Path $PSScriptRoot "..\data\dictionaries\naaccr-items-v25.json"

Write-Host "Reading XML from: $xmlPath"

[xml]$xml = Get-Content -Path $xmlPath -Encoding UTF8

$items = @()
foreach ($item in $xml.NaaccrDataItemExport.NaaccrDataItems.NaaccrDataItem) {
    $xmlId = $item.XmlNaaccrId
    if (-not [string]::IsNullOrWhiteSpace($xmlId)) {
        $items += @{
            n = $item.ItemNumber
            name = $item.ItemName
            id = $xmlId
            p = $item.XmlParentId
        }
    }
}

Write-Host "Found $($items.Count) items"

$json = $items | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.Encoding]::UTF8)

Write-Host "Created JSON at: $jsonPath"

