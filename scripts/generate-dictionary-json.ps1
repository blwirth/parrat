# generate-dictionary-json.ps1
# Parse an XML dictionary and create a compact JSON file.
# Supports two XML formats:
#   1. NAACCR Data Dictionary Export (from apps.naaccr.org) — NaaccrDataItemExport root
#   2. imsweb/naaccr-xml base dictionary — NaaccrDictionary root with ItemDef elements
#
# Usage:
#   .\generate-dictionary-json.ps1                          # defaults to v25 NAACCR export
#   .\generate-dictionary-json.ps1 -XmlPath <path> -Version 26

param(
    [string]$XmlPath,
    [int]$Version = 25
)

$dictDir = Join-Path $PSScriptRoot "..\data\dictionaries"

if (-not $XmlPath) {
    $XmlPath = Join-Path $dictDir "naaccr-data-dictionary-v$Version.xml"
}
$jsonPath = Join-Path $dictDir "naaccr-items-v$Version.json"

Write-Host "Reading XML from: $XmlPath"

[xml]$xml = Get-Content -Path $XmlPath -Encoding UTF8

$items = @()

# Detect format by root element
$rootName = $xml.DocumentElement.LocalName

if ($rootName -eq "NaaccrDataItemExport") {
    # Format 1: NAACCR Data Dictionary Export (apps.naaccr.org)
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
} elseif ($rootName -eq "NaaccrDictionary") {
    # Format 2: imsweb/naaccr-xml base dictionary (GitHub)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsUri = $xml.DocumentElement.NamespaceURI
    if ($nsUri) { $ns.AddNamespace("d", $nsUri) }

    $xpath = if ($nsUri) { "//d:ItemDef" } else { "//ItemDef" }
    $nodes = $xml.SelectNodes($xpath, $ns)

    foreach ($node in $nodes) {
        $xmlId = $node.GetAttribute("naaccrId")
        if (-not [string]::IsNullOrWhiteSpace($xmlId)) {
            $items += @{
                n = $node.GetAttribute("naaccrNum")
                name = $node.GetAttribute("naaccrName")
                id = $xmlId
                p = $node.GetAttribute("parentXmlElement")
            }
        }
    }
} else {
    Write-Error "Unknown XML format: root element is '$rootName'"
    exit 1
}

Write-Host "Found $($items.Count) items"

$json = $items | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.Encoding]::UTF8)

Write-Host "Created JSON at: $jsonPath"
