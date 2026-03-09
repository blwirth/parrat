# export-config.ps1
# Save and load export field configurations as JSON

$script:ExportConfigPath = Join-Path $PSScriptRoot "..\config\export-configs"

function Get-ExportConfigPath {
    <#
    .SYNOPSIS
        Gets the path to the export configurations folder.
    .DESCRIPTION
        Creates the folder if it doesn't exist.
    #>

    if (-not (Test-Path $script:ExportConfigPath)) {
        New-Item -ItemType Directory -Path $script:ExportConfigPath -Force | Out-Null
    }

    return $script:ExportConfigPath
}

function Get-DefaultFieldList {
    <#
    .SYNOPSIS
        Returns the default field list for XML CSV exports.
    .DESCRIPTION
        These are the original hardcoded fields from the export functions.
    #>

    return @(
        @{ XmlId = "patientIdNumber"; IsCustom = $false },
        @{ XmlId = "nameLast"; IsCustom = $false },
        @{ XmlId = "nameFirst"; IsCustom = $false },
        @{ XmlId = "nameMiddle"; IsCustom = $false },
        @{ XmlId = "dateOfBirth"; IsCustom = $false },
        @{ XmlId = "reportingFacility"; IsCustom = $false },
        @{ XmlId = "dateOfDiagnosis"; IsCustom = $false },
        @{ XmlId = "pathReportNumber1"; IsCustom = $false },
        @{ XmlId = "primarySite"; IsCustom = $false },
        @{ XmlId = "histologicTypeIcdO3"; IsCustom = $false },
        @{ XmlId = "behaviorCodeIcdO3"; IsCustom = $false }
    )
}

function New-ExportConfig {
    <#
    .SYNOPSIS
        Creates a new export configuration object.
    .PARAMETER Name
        Name for the configuration.
    .PARAMETER Fields
        Array of field objects with XmlId, IsCustom, and optionally ParentElement.
    .PARAMETER Version
        NAACCR dictionary version (default 25).
    #>
    param(
        [string]$Name = "Unnamed Configuration",
        [array]$Fields = @(),
        [int]$Version = 25
    )

    return @{
        Name = $Name
        Version = $Version
        Fields = $Fields
        CreatedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Save-ExportConfig {
    <#
    .SYNOPSIS
        Saves an export configuration to a JSON file.
    .PARAMETER Config
        The configuration object to save.
    .PARAMETER FileName
        Optional filename. If not provided, uses the config name.
    .PARAMETER Path
        Optional path. Defaults to export-configs folder.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [string]$FileName,

        [string]$Path
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Get-ExportConfigPath
        }

        if ([string]::IsNullOrWhiteSpace($FileName)) {
            # Sanitize config name for filename
            $safeName = $Config.Name -replace '[^\w\-]', '_'
            $FileName = "$safeName.json"
        }

        # Ensure .json extension
        if (-not $FileName.EndsWith(".json")) {
            $FileName = "$FileName.json"
        }

        $fullPath = Join-Path $Path $FileName

        # Convert to JSON and save
        $jsonContent = $Config | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($fullPath, $jsonContent, [System.Text.Encoding]::UTF8)

        return @{
            Success = $true
            Path = $fullPath
            Message = "Configuration saved successfully"
        }
    }
    catch {
        return @{
            Success = $false
            Path = $null
            Message = "Error saving configuration: $($_.Exception.Message)"
        }
    }
}

function Get-ExportConfig {
    <#
    .SYNOPSIS
        Loads an export configuration from a JSON file.
    .PARAMETER FilePath
        Full path to the JSON configuration file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        if (-not (Test-Path $FilePath)) {
            return @{
                Success = $false
                Config = $null
                Message = "Configuration file not found: $FilePath"
            }
        }

        $jsonContent = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        $config = $jsonContent | ConvertFrom-Json

        # Convert PSCustomObject to hashtable for consistency
        $configHashtable = @{
            Name = $config.Name
            Version = $config.Version
            CreatedDate = $config.CreatedDate
            Fields = @()
        }

        foreach ($field in $config.Fields) {
            $fieldHashtable = @{
                XmlId = $field.XmlId
                IsCustom = $field.IsCustom
            }

            # Include ParentElement for custom fields
            if ($field.PSObject.Properties.Name -contains "ParentElement") {
                $fieldHashtable.ParentElement = $field.ParentElement
            }

            $configHashtable.Fields += $fieldHashtable
        }

        return @{
            Success = $true
            Config = $configHashtable
            Message = "Configuration loaded successfully"
        }
    }
    catch {
        return @{
            Success = $false
            Config = $null
            Message = "Error loading configuration: $($_.Exception.Message)"
        }
    }
}

function Get-AvailableExportConfigs {
    <#
    .SYNOPSIS
        Gets a list of all available export configuration files.
    .DESCRIPTION
        Returns file info for all .json files in the export-configs folder.
    #>

    $configPath = Get-ExportConfigPath

    $configs = Get-ChildItem -Path $configPath -Filter "*.json" -File | ForEach-Object {
        try {
            $result = Get-ExportConfig -FilePath $_.FullName
            if ($result.Success) {
                @{
                    FileName = $_.Name
                    FullPath = $_.FullName
                    Name = $result.Config.Name
                    FieldCount = $result.Config.Fields.Count
                    Version = $result.Config.Version
                    CreatedDate = $result.Config.CreatedDate
                }
            }
        }
        catch {
            # Skip invalid config files
            $null = $_.Exception
        }
    }

    return $configs
}

function Convert-FieldListToXmlIds {
    <#
    .SYNOPSIS
        Converts a config's field list to a simple array of XML IDs.
    .DESCRIPTION
        Used when passing field list to export functions.
    .PARAMETER Fields
        Array of field objects from a configuration.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Fields
    )

    return $Fields | ForEach-Object { $_.XmlId }
}

function Get-CustomFieldsFromConfig {
    <#
    .SYNOPSIS
        Extracts custom fields and their parent elements from a configuration.
    .DESCRIPTION
        Returns a hashtable mapping custom field XmlIds to their ParentElements.
    .PARAMETER Fields
        Array of field objects from a configuration.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Fields
    )

    $customFields = @{}

    foreach ($field in $Fields) {
        if ($field.IsCustom -eq $true) {
            $parentElement = if ($field.ContainsKey("ParentElement")) { $field.ParentElement } else { "Tumor" }
            $customFields[$field.XmlId] = $parentElement
        }
    }

    return $customFields
}

function Initialize-DefaultExportConfig {
    <#
    .SYNOPSIS
        Creates the default export configuration file if it doesn't exist.
    #>

    $configPath = Get-ExportConfigPath
    $defaultPath = Join-Path $configPath "default.json"

    if (-not (Test-Path $defaultPath)) {
        $defaultConfig = New-ExportConfig -Name "Default" -Fields (Get-DefaultFieldList) -Version 25
        Save-ExportConfig -Config $defaultConfig -FileName "default.json"
    }
}

