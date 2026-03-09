# btnManageTables.ps1
# Coding Table Editor - Manage Laterality, Topography, and Skin Topography lookup tables

# Compute dictionary paths at load time (uses $script:DictionaryDir from syntax-helpers.ps1)
$script:LateralityFilePath = Join-Path $script:DictionaryDir "Laterality.json"
$script:TopographyFilePath = Join-Path $script:DictionaryDir "Topography.jsonl"
$script:SkinTopoFilePath = Join-Path $script:DictionaryDir "TopographyMelanoma.jsonl"

function Read-CodingTableFile {
    <#
    .SYNOPSIS
    Read a coding table file (JSON array or JSONL format)

    .PARAMETER Path
    Path to the file

    .PARAMETER TableType
    'laterality' for JSON array, 'topography' for JSONL

    .OUTPUTS
    Array of objects with Code (and SearchPhrase for topography)
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('laterality','topography')][string]$TableType
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    $items = @()

    if ($TableType -eq 'laterality') {
        # JSON array of code strings
        $json = [System.IO.File]::ReadAllText($Path)
        $array = $json | ConvertFrom-Json

        foreach ($code in $array) {
            $items += [PSCustomObject]@{
                Code = [string]$code
            }
        }
    }
    else {
        # JSONL format with Code and SearchPhrase
        $lines = [System.IO.File]::ReadAllLines($Path)

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $item = $line | ConvertFrom-Json
                if ($item.Code) {
                    $items += [PSCustomObject]@{
                        Code = [string]$item.Code
                        SearchPhrase = [string]$item.SearchPhrase
                    }
                }
            }
            catch {
                Write-Warning "Failed to parse JSON line: $line"
            }
        }
    }

    return $items
}

function Write-CodingTableFile {
    <#
    .SYNOPSIS
    Write a coding table file (JSON array or JSONL format)

    .PARAMETER Path
    Path to the file

    .PARAMETER TableType
    'laterality' for JSON array, 'topography' for JSONL

    .PARAMETER Data
    Array of objects to write
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('laterality','topography')][string]$TableType,
        [Parameter(Mandatory=$true)][array]$Data
    )

    if ($TableType -eq 'laterality') {
        # Write as JSON array of code strings
        $codes = @()
        foreach ($item in $Data) {
            if (-not [string]::IsNullOrWhiteSpace($item.Code)) {
                $codes += $item.Code
            }
        }

        $json = $codes | ConvertTo-Json
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
    }
    else {
        # Write as JSONL
        $lines = @()
        foreach ($item in $Data) {
            if (-not [string]::IsNullOrWhiteSpace($item.Code)) {
                $obj = @{
                    Code = $item.Code
                    SearchPhrase = $item.SearchPhrase
                }
                $lines += ($obj | ConvertTo-Json -Compress)
            }
        }

        [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::UTF8)
    }
}

function Format-SiteCode {
    <#
    .SYNOPSIS
    Format a site code to standard format (C followed by 3 digits)

    .PARAMETER Code
    Raw code input

    .OUTPUTS
    Formatted code string or original if invalid
    #>
    param([string]$Code)

    $Code = $Code.Trim().ToUpper()

    # Already in correct format
    if ($Code -match '^C\d{3}$') {
        return $Code
    }

    # Just digits - add C prefix and pad
    if ($Code -match '^\d{1,3}$') {
        return "C" + $Code.PadLeft(3, '0')
    }

    # C followed by 1-2 digits - pad
    if ($Code -match '^C\d{1,2}$') {
        $digits = $Code.Substring(1)
        return "C" + $digits.PadLeft(3, '0')
    }

    # Return as-is if we can't format it
    return $Code
}

function Get-BtnManageTablesHandler {
    <#
    .SYNOPSIS
    Returns a handler that populates the Manage Coding Tables dropdown menu
    #>
    param(
        [hashtable]$Controls
    )

    return {
        param($toolStripButton, $e)

        # Clear existing items
        $toolStripButton.DropDownItems.Clear()

        # Laterality
        $menuItemLaterality = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemLaterality.Text = "Laterality"
        $menuItemLaterality.Add_Click({
            Show-CodingTableEditor -FilePath $script:LateralityFilePath -TableType 'laterality' -Title "Laterality"
        })
        [void]$toolStripButton.DropDownItems.Add($menuItemLaterality)

        # Topography
        $menuItemTopography = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemTopography.Text = "Topography"
        $menuItemTopography.Add_Click({
            Show-CodingTableEditor -FilePath $script:TopographyFilePath -TableType 'topography' -Title "Topography"
        })
        [void]$toolStripButton.DropDownItems.Add($menuItemTopography)

        # Skin Topography (Melanoma)
        $menuItemSkinTopo = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSkinTopo.Text = "Skin Topography"
        $menuItemSkinTopo.Add_Click({
            Show-CodingTableEditor -FilePath $script:SkinTopoFilePath -TableType 'topography' -Title "Skin Topography"
        })
        [void]$toolStripButton.DropDownItems.Add($menuItemSkinTopo)

        # Separator
        [void]$toolStripButton.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

        # Site Coding Rules
        $menuItemSiteCodingRules = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemSiteCodingRules.Text = "Site Coding Rules"
        $menuItemSiteCodingRules.Add_Click({
            Show-SiteCodingRulesEditor
        })
        [void]$toolStripButton.DropDownItems.Add($menuItemSiteCodingRules)
    }
}
