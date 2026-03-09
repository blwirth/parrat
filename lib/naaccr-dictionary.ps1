# naaccr-dictionary.ps1
# Load and parse NAACCR data dictionary for field lookups

$script:NaaccrDictionary = @{}
$script:NaaccrDictionaryLoaded = $false

function Initialize-NaaccrDictionary {
    <#
    .SYNOPSIS
        Loads the NAACCR data dictionary from JSON file.
    .DESCRIPTION
        Loads the compact JSON dictionary file created from the XML source.
        Falls back to parsing XML if JSON doesn't exist.
    .PARAMETER Version
        Dictionary version to load (24 or 25). Defaults to 25.
    #>
    param(
        [int]$Version = 25
    )

    if ($script:NaaccrDictionaryLoaded) {
        return $true
    }

    $basePath = $script:DictionaryDir
    $jsonPath = Join-Path $basePath "naaccr-items-v$Version.json"
    $xmlPath = Join-Path $basePath "naaccr-data-dictionary-v$Version.xml"

    try {
        # Prefer JSON file (faster, more reliable)
        if (Test-Path $jsonPath) {
            $jsonContent = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
            $items = $jsonContent | ConvertFrom-Json
            
            foreach ($item in $items) {
                $xmlId = $item.id
                if (-not [string]::IsNullOrWhiteSpace($xmlId)) {
                    $sortKey = 999999
                    [void][int]::TryParse($item.n, [ref]$sortKey)
                    $script:NaaccrDictionary[$xmlId] = @{
                        Number = $item.n
                        NumberInt = $sortKey
                        Name = $item.name
                        XmlId = $xmlId
                        ParentElement = $item.p
                    }
                }
            }
            
            $script:NaaccrDictionaryLoaded = $true
            Write-Verbose "Loaded $($script:NaaccrDictionary.Count) NAACCR dictionary items from JSON"
            return $true
        }
        # Fallback to XML if JSON doesn't exist
        elseif (Test-Path $xmlPath) {
            [xml]$xml = Get-Content -Path $xmlPath -Encoding UTF8
            
            foreach ($item in $xml.NaaccrDataItemExport.NaaccrDataItems.NaaccrDataItem) {
                $xmlId = $item.XmlNaaccrId
                if (-not [string]::IsNullOrWhiteSpace($xmlId)) {
                    $sortKey = 999999
                    [void][int]::TryParse($item.ItemNumber, [ref]$sortKey)
                    $script:NaaccrDictionary[$xmlId] = @{
                        Number = $item.ItemNumber
                        NumberInt = $sortKey
                        Name = $item.ItemName
                        XmlId = $xmlId
                        ParentElement = $item.XmlParentId
                    }
                }
            }
            
            $script:NaaccrDictionaryLoaded = $true
            Write-Verbose "Loaded $($script:NaaccrDictionary.Count) NAACCR dictionary items from XML"
            return $true
        }
        else {
            Write-Warning "NAACCR dictionary not found at: $jsonPath or $xmlPath"
            return $false
        }
    }
    catch {
        Write-Warning "Error loading NAACCR dictionary: $($_.Exception.Message)"
        return $false
    }
}

function Get-NaaccrDictionary {
    <#
    .SYNOPSIS
        Returns all items from the NAACCR dictionary.
    .DESCRIPTION
        Returns an array of all dictionary items sorted by data item number.
    #>
    
    if (-not $script:NaaccrDictionaryLoaded) {
        Initialize-NaaccrDictionary | Out-Null
    }
    
    # Return as array sorted by pre-computed integer key
    $items = $script:NaaccrDictionary.Values | Sort-Object { $_.NumberInt }
    return $items
}

function Get-NaaccrItemByXmlId {
    <#
    .SYNOPSIS
        Looks up a single NAACCR item by its XML ID.
    .PARAMETER XmlId
        The XML NAACCR ID to look up (e.g., "patientIdNumber").
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlId
    )
    
    if (-not $script:NaaccrDictionaryLoaded) {
        Initialize-NaaccrDictionary | Out-Null
    }
    
    if ($script:NaaccrDictionary.ContainsKey($XmlId)) {
        return $script:NaaccrDictionary[$XmlId]
    }
    
    return $null
}

function Get-NaaccrParentElement {
    <#
    .SYNOPSIS
        Gets the parent XML element for a NAACCR field.
    .DESCRIPTION
        Returns "Patient", "Tumor", or "NaaccrData" based on the dictionary.
        For unknown fields, defaults to "Tumor".
    .PARAMETER XmlId
        The XML NAACCR ID to look up.
    .PARAMETER CustomFields
        Optional hashtable of custom field definitions with their parent elements.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlId,
        
        [hashtable]$CustomFields = @{}
    )
    
    if (-not $script:NaaccrDictionaryLoaded) {
        Initialize-NaaccrDictionary | Out-Null
    }
    
    # Check custom fields first
    if ($CustomFields.ContainsKey($XmlId)) {
        return $CustomFields[$XmlId]
    }
    
    # Check dictionary
    if ($script:NaaccrDictionary.ContainsKey($XmlId)) {
        $parent = $script:NaaccrDictionary[$XmlId].ParentElement
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            return $parent
        }
    }
    
    # Default to Tumor for unknown fields
    return "Tumor"
}

function Search-NaaccrDictionary {
    <#
    .SYNOPSIS
        Searches the NAACCR dictionary by name or XML ID.
    .PARAMETER SearchText
        Text to search for (case-insensitive, partial match).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchText
    )
    
    if (-not $script:NaaccrDictionaryLoaded) {
        Initialize-NaaccrDictionary | Out-Null
    }
    
    $searchLower = $SearchText.ToLower()
    
    $results = $script:NaaccrDictionary.Values | Where-Object {
        $_.Name.ToLower().Contains($searchLower) -or
        $_.XmlId.ToLower().Contains($searchLower) -or
        $_.Number -eq $SearchText
    } | Sort-Object { 
        $num = 0
        if ([int]::TryParse($_.Number, [ref]$num)) { $num } else { 999999 }
    }
    
    return $results
}

function Get-NaaccrDictionaryDisplayName {
    <#
    .SYNOPSIS
        Gets a display-friendly name for a NAACCR field.
    .DESCRIPTION
        Returns "Name (xmlId)" format for display in UI.
    .PARAMETER XmlId
        The XML NAACCR ID to look up.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlId
    )
    
    $item = Get-NaaccrItemByXmlId -XmlId $XmlId
    
    if ($null -ne $item) {
        return "$($item.Name) ($($item.XmlId))"
    }
    
    # For custom/unknown fields, just return the ID
    return "$XmlId (custom)"
}
