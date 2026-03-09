# test-site-laterality.ps1
# Test site/laterality heuristics on custom text

. "$PSScriptRoot\assign-site-laterality.ps1"

function Test-SiteLateralityHeuristics {
    <#
    .SYNOPSIS
    Run site/laterality heuristics on input text and return detailed result

    .PARAMETER Text
    The pathology text to analyze

    .OUTPUTS
    Hashtable with site code, description, match type, pattern name/priority, laterality, etc.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Text
    )

    $scriptDir = $PSScriptRoot

    $maps = Get-CachedMaps -ScriptDir $scriptDir
    $topoMap = $maps.TopoMap
    $melTopoMap = $maps.MelTopoMap
    $lateralityCodes = $maps.LateralityCodes
    $siteCodingRules = $maps.SiteCodingRules

    $low = $Text.ToLower()

    $result = @{
        SiteCode = ""
        SiteDescription = ""
        MatchType = "none"
        MatchedPhrase = ""
        PatternPriority = ""
        LateralityCode = ""
        LateralityDescription = ""
        SiteRequiresLaterality = $false
    }

    # Site Assignment Tiers:
    # 1. Site coding rules (from SiteCodingRules.jsonl)
    $patternMatched = $false
    $matchedPattern = $null
    foreach ($pattern in $siteCodingRules) {
        $testResult = Test-SiteCodingRule -Pattern $pattern -TextLow $low -TopoMap $topoMap
        if ($testResult.Matched) {
            # Use TopoCode from topo-template match, otherwise use pattern's Code
            # Skip if Code is {topo} but no TopoCode was found
            if ($testResult.TopoCode) {
                $result.SiteCode = $testResult.TopoCode
            }
            elseif ($pattern.Code -ne "{topo}") {
                $result.SiteCode = $pattern.Code
            }
            else {
                # {topo} pattern matched but no TopoCode - skip this pattern
                continue
            }
            $result.MatchType = "site-coding-rule"
            $result.MatchedPhrase = $testResult.MatchedTerm
            $result.PatternPriority = [string]$pattern.Priority
            $matchedPattern = $pattern
            $patternMatched = $true
            break
        }
    }

    if (-not $patternMatched) {
        # 2. Melanoma dictionary - if "melanoma" found
        $hasMel = $low.Contains("melanoma")

        if ($hasMel) {
            $bestCode = ""
            $bestPos = 0
            $bestPhrase = ""

            foreach ($row in $melTopoMap) {
                $code = $row.Code
                $phrase = $row.SearchPhrase

                $escapedPhrase = [regex]::Escape($phrase)
                $regexPattern = "(?<![a-zA-Z])$escapedPhrase(?![a-zA-Z])"

                $match = [regex]::Match($low, $regexPattern)
                if ($match.Success) {
                    $p = $match.Index + 1
                    if ($bestPos -eq 0 -or $p -lt $bestPos) {
                        $bestPos = $p
                        $bestCode = $code
                        $bestPhrase = $phrase
                    }
                }
            }

            if ($bestCode) {
                $result.SiteCode = $bestCode
                $result.MatchType = "melanoma-dict"
                $result.MatchedPhrase = $bestPhrase
            }
            else {
                $result.SiteCode = "C449"
                $result.SiteDescription = "Skin, NOS"
                $result.MatchType = "melanoma-dict"
                $result.MatchedPhrase = "melanoma (fallback)"
            }
        }
        else {
            # 3. Standard dictionary - earliest match wins
            $bestCode = ""
            $bestPos = 0
            $bestPhrase = ""

            foreach ($row in $topoMap) {
                $code = $row.Code
                $phrase = $row.SearchPhrase

                $escapedPhrase = [regex]::Escape($phrase)
                $regexPattern = "(?<![a-zA-Z])$escapedPhrase(?![a-zA-Z])"

                $match = [regex]::Match($low, $regexPattern)
                if ($match.Success) {
                    $p = $match.Index + 1
                    if ($bestPos -eq 0 -or $p -lt $bestPos) {
                        $bestPos = $p
                        $bestCode = $code
                        $bestPhrase = $phrase
                    }
                }
            }

            if ($bestCode) {
                $result.SiteCode = $bestCode
                $result.MatchType = "standard-dict"
                $result.MatchedPhrase = $bestPhrase
            }
        }
    }

    # Look up site description if we have a code but no description yet
    if ($result.SiteCode -and -not $result.SiteDescription) {
        $result.SiteDescription = "Site $($result.SiteCode)"
    }

    if ($result.SiteCode) {
        $result.SiteRequiresLaterality = $lateralityCodes.ContainsKey($result.SiteCode)

        # Check if pattern has ForceLaterality set
        if ($matchedPattern -and $matchedPattern.ForceLaterality) {
            $result.LateralityCode = $matchedPattern.ForceLaterality
            $result.LateralityDescription = "Unknown (forced by pattern)"
        }
        elseif ($result.SiteRequiresLaterality) {
            $leftMatch = [regex]::Match($low, '\bleft\b')
            $rightMatch = [regex]::Match($low, '\bright\b')

            $hasLeft = $leftMatch.Success
            $hasRight = $rightMatch.Success

            if ($hasLeft -and $hasRight) {
                $result.LateralityCode = "9"
                $result.LateralityDescription = "Unknown (both left and right found)"
            }
            elseif ($hasLeft) {
                $result.LateralityCode = "2"
                $result.LateralityDescription = "Left"
            }
            elseif ($hasRight) {
                $result.LateralityCode = "1"
                $result.LateralityDescription = "Right"
            }
            else {
                $result.LateralityCode = "9"
                $result.LateralityDescription = "Unknown"
            }
        }
        else {
            $result.LateralityCode = "0"
            $result.LateralityDescription = "Not Applicable"
        }
    }

    return $result
}

