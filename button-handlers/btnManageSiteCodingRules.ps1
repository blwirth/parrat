# btnManageSiteCodingRules.ps1
# Site Coding Rules Editor - Manage site coding heuristics with AND/OR logic support

$script:SiteCodingRulesFilePath = Join-Path $script:DictionaryDir "SiteCodingRules.jsonl"

function Read-SiteCodingRulesFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @()
    }

    $patterns = @()
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    # Remove BOM if present
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }
    $lines = $content -split "`r?`n"

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $pattern = $line | ConvertFrom-Json
            # If the parsed result is an array, extract the object element
            if ($pattern -is [System.Array]) {
                $pattern = $pattern | Where-Object { $_ -is [PSCustomObject] } | Select-Object -First 1
            }
            # Only add valid patterns (must have a Code)
            if ($pattern -and -not [string]::IsNullOrWhiteSpace($pattern.Code)) {
                $patterns += $pattern
            }
        }
        catch {
            Write-Warning "Failed to parse site coding rule line: $line - $($_.Exception.Message)"
        }
    }

    return $patterns
}

function Write-SiteCodingRulesFile {
    param(
        [string]$Path,
        [array]$Patterns
    )

    $lines = @()
    foreach ($pattern in $Patterns) {
        # Allow {topo} as special Code for dynamic lookup, or any non-empty Code
        $code = $pattern.Code
        if (-not [string]::IsNullOrWhiteSpace($code) -or $code -eq "{topo}") {
            $lines += ($pattern | ConvertTo-Json -Compress -Depth 10)
        }
        elseif ($pattern.Expression) {
            # Check if pattern has topo-template expressions - save even with empty Code
            $hasTopoTemplate = $false
            foreach ($expr in $pattern.Expression) {
                if ($expr.type -eq "topo-template") {
                    $hasTopoTemplate = $true
                    break
                }
            }
            if ($hasTopoTemplate) {
                # Default Code to {topo} for topo-template patterns
                $pattern.Code = "{topo}"
                $lines += ($pattern | ConvertTo-Json -Compress -Depth 10)
            }
        }
    }

    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::UTF8)
}

function Get-ExpressionPreview {
    param($Expression, $Logic)

    # Handle null or empty
    if ($null -eq $Expression) {
        return "(no terms)"
    }

    # Ensure it's an array we can iterate
    $exprArray = @($Expression)
    if ($exprArray.Count -eq 0) {
        return "(no terms)"
    }

    $parts = @()
    foreach ($item in $exprArray) {
        if ($null -eq $item) { continue }

        $itemType = $item.type
        if ($itemType -eq "term") {
            $parts += $item.value
        }
        elseif ($itemType -eq "group") {
            $termsArray = @($item.terms)
            $groupTerms = $termsArray -join " $($item.logic) "
            $parts += "($groupTerms)"
        }
        elseif ($itemType -eq "topo-template") {
            $parts += "{topo}: $($item.template)"
        }
    }

    if ($parts.Count -eq 0) {
        return "(no terms)"
    }

    $preview = $parts -join " $Logic "
    if ($preview.Length -gt 50) {
        $preview = $preview.Substring(0, 47) + "..."
    }

    return $preview
}
