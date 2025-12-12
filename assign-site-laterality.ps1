# assign-site-laterality.ps1
# NAACCR XML primary site and laterality assignment utilities

. "$PSScriptRoot\xml-helpers.ps1"

# Cache for loaded Excel maps to avoid reloading on every call
# More important if we don't have the .json and .jsonl files created
# Would otherwise take about 10s per call
$script:TopoMapCache = $null
$script:MelTopoMapCache = $null
$script:LateralityCodesCache = $null
$script:TopoMapCacheTime = $null
$script:MelTopoMapCacheTime = $null
$script:LateralityCodesCacheTime = $null

# Load topography lookup tables
function Read-TopographyExcel {
    param([string]$Path)

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $wb = $excel.Workbooks.Open($Path)
    $ws = $wb.Sheets.Item(1)

    $rows = @()

    $used     = $ws.UsedRange
    $rowCount = $used.Rows.Count
    $colCount = $used.Columns.Count

    $codeCol   = $null
    $phraseCol = $null

    for ($c = 1; $c -le $colCount; $c++) {
        $header = [string]$ws.Cells.Item(1, $c).Text
        $header = $header.Trim()

        if ($header -eq "Code") {
            $codeCol = $c
        }
        elseif ($header -eq "SearchPhrase") {
            $phraseCol = $c
        }
    }

    if (-not $codeCol -or -not $phraseCol) {
        $wb.Close($false)
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)   | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb)   | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)| Out-Null
        throw "Could not find 'Code' and 'SearchPhrase' headers in $Path"
    }

    for ($r = 2; $r -le $rowCount; $r++) {
        $cellCode   = $ws.Cells.Item($r, $codeCol)
        $cellPhrase = $ws.Cells.Item($r, $phraseCol)

        $code   = [string]$cellCode.Text
        $phrase = [string]$cellPhrase.Text

        $code   = $code.Trim()
        $phrase = $phrase.Trim()

        if ($code -and $phrase) {
            if ($code -match '^\d{3}$') {
                $code = "C$code"
            }
            if ($code -match '^C\d{1,3}$') {
                $digits = $code.Substring(1)
                $digits = $digits.PadRight(3, '0')
                $code   = "C$digits"
            }

            $rows += [PSCustomObject]@{
                Code         = $code
                SearchPhrase = $phrase.ToLower()
            }
        }
    }

    $wb.Close($false)
    $excel.Quit()

    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)    | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb)    | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

    return $rows
}

# Load laterality lookup table
function Read-LateralityExcel {
    param([string]$Path)

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $wb = $excel.Workbooks.Open($Path)
    $ws = $wb.Sheets.Item(1)

    $codes = @{}

    $used     = $ws.UsedRange
    $rowCount = $used.Rows.Count
    $colCount = $used.Columns.Count

    $codeCol = $null

    for ($c = 1; $c -le $colCount; $c++) {
        $header = [string]$ws.Cells.Item(1, $c).Text
        $header = $header.Trim()

        if ($header -eq "Code") {
            $codeCol = $c
            break
        }
    }

    if (-not $codeCol) {
        $wb.Close($false)
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)   | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb)   | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)| Out-Null
        throw "Could not find 'Code' header in $Path"
    }

    for ($r = 2; $r -le $rowCount; $r++) {
        $cellCode = $ws.Cells.Item($r, $codeCol)
        $code = [string]$cellCode.Text
        $code = $code.Trim()

        if ($code) {
            # Normalize code format
            if ($code -match '^\d{3}$') {
                $code = "C$code"
            }
            if ($code -match '^C\d{1,3}$') {
                $digits = $code.Substring(1)
                $digits = $digits.PadRight(3, '0')
                $code = "C$digits"
            }
            
            $codes[$code] = $true
        }
    }

    $wb.Close($false)
    $excel.Quit()

    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)    | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb)    | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

    return $codes
}

# Fast JSON loading functions (much faster than Excel COM objects)
function Read-TopographyJson {
    param([string]$Path)
    
    $items = @()
    
    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }
    
    # Read all lines at once for better performance
    $lines = [System.IO.File]::ReadAllLines($Path)
    
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        try {
            $item = $line | ConvertFrom-Json
            if ($item.Code -and $item.SearchPhrase) {
                $items += $item
            }
        }
        catch {
            Write-Warning "Failed to parse JSON line: $line"
        }
    }
    
    return $items
}

function Read-LateralityJson {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }
    
    $json = [System.IO.File]::ReadAllText($Path)
    $codes = @{}
    $array = $json | ConvertFrom-Json
    
    foreach ($code in $array) {
        $codes[$code] = $true
    }
    
    return $codes
}

function Get-BestCode {
    param($Map, $TextLow)

    $bestCode = ""
    $bestPos  = 0

    foreach ($row in $Map) {
        $code   = $row.Code
        $phrase = $row.SearchPhrase
        $pos = $TextLow.IndexOf($phrase)
        if ($pos -ge 0) {
            $p = $pos + 1
            if ($bestPos -eq 0 -or $p -lt $bestPos) {
                $bestPos  = $p
                $bestCode = $code
            }
        }
    }

    return $bestCode
}

function Get-Laterality {
    param($TextLow)

    # Use word boundaries to match only whole words
    $leftMatch = [regex]::Match($TextLow, '\bleft\b')
    $rightMatch = [regex]::Match($TextLow, '\bright\b')

    $pLeft = if ($leftMatch.Success) { $leftMatch.Index } else { -1 }
    $pRight = if ($rightMatch.Success) { $rightMatch.Index } else { -1 }

    if ($pLeft -lt 0 -and $pRight -lt 0) { return "" }
    if ($pLeft -ge 0 -and ($pRight -lt 0 -or $pLeft -lt $pRight)) { return "2" }
    return "1"
}

function Get-ItemValue {
    param(
        [System.Xml.XmlNode]$Context,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$Id
    )
    
    $node = $Context.SelectSingleNode("./n:Item[@naaccrId='$Id']", $NsMgr)
    if ($node) { return $node.InnerText }
    return ""
}

function Get-CachedMaps {
    param(
        [string]$ScriptDir
    )
    
    # Prefer JSON files (much faster), fallback to Excel
    $topoJson    = Join-Path $ScriptDir "Topography.jsonl"
    $melTopoJson = Join-Path $ScriptDir "TopographyMelanoma.jsonl"
    $latJson     = Join-Path $ScriptDir "Laterality.json"
    $topoXlsx    = Join-Path $ScriptDir "Topography.xlsx"
    $melTopoXlsx = Join-Path $ScriptDir "TopographyMelanoma.xlsx"
    $latXlsx     = Join-Path $ScriptDir "Laterality.xlsx"

    # Determine which files to use (prefer JSON)
    $useTopoJson = Test-Path $topoJson
    $useMelTopoJson = Test-Path $melTopoJson
    $useLatJson = Test-Path $latJson
    
    # Validate that at least one format exists for each file
    if (-not $useTopoJson -and -not (Test-Path $topoXlsx)) {
        throw "Missing Topography file (neither .jsonl nor .xlsx found) in script folder: $ScriptDir"
    }
    if (-not $useMelTopoJson -and -not (Test-Path $melTopoXlsx)) {
        throw "Missing TopographyMelanoma file (neither .jsonl nor .xlsx found) in script folder: $ScriptDir"
    }
    if (-not $useLatJson -and -not (Test-Path $latXlsx)) {
        throw "Missing Laterality file (neither .json nor .xlsx found) in script folder: $ScriptDir"
    }

    $loadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $needsReload = $false
    $sourceType = @()
    
    # Check if we need to reload Topography map
    $topoFile = if ($useTopoJson) { $topoJson } else { $topoXlsx }
    $topoFileTime = (Get-Item $topoFile).LastWriteTime
    
    if ($null -eq $script:TopoMapCache -or $null -eq $script:TopoMapCacheTime -or $topoFileTime -gt $script:TopoMapCacheTime) {
        if ($useTopoJson) {
            Write-Host "Loading Topography.jsonl..." -ForegroundColor Cyan
            $script:TopoMapCache = Read-TopographyJson $topoJson |
                Where-Object { $_.Code -and $_.SearchPhrase -and $_.Code -notlike 'C77?' }
            $sourceType += "JSON"
        } else {
            Write-Host "Loading Topography.xlsx..." -ForegroundColor Cyan
            $script:TopoMapCache = Read-TopographyExcel $topoXlsx |
                Where-Object { $_.Code -and $_.SearchPhrase -and $_.Code -notlike 'C77?' }
            $sourceType += "Excel"
        }
        $script:TopoMapCacheTime = $topoFileTime
        $needsReload = $true
    }
    
    # Check if we need to reload Melanoma Topography map
    $melTopoFile = if ($useMelTopoJson) { $melTopoJson } else { $melTopoXlsx }
    $melTopoFileTime = (Get-Item $melTopoFile).LastWriteTime
    
    if ($null -eq $script:MelTopoMapCache -or $null -eq $script:MelTopoMapCacheTime -or $melTopoFileTime -gt $script:MelTopoMapCacheTime) {
        if ($useMelTopoJson) {
            Write-Host "Loading TopographyMelanoma.jsonl..." -ForegroundColor Cyan
            $script:MelTopoMapCache = Read-TopographyJson $melTopoJson |
                Where-Object { $_.Code -and $_.SearchPhrase }
            $sourceType += "JSON"
        } else {
            Write-Host "Loading TopographyMelanoma.xlsx..." -ForegroundColor Cyan
            $script:MelTopoMapCache = Read-TopographyExcel $melTopoXlsx |
                Where-Object { $_.Code -and $_.SearchPhrase }
            $sourceType += "Excel"
        }
        $script:MelTopoMapCacheTime = $melTopoFileTime
        $needsReload = $true
    }
    
    # Check if we need to reload Laterality codes
    $latFile = if ($useLatJson) { $latJson } else { $latXlsx }
    $latFileTime = (Get-Item $latFile).LastWriteTime
    
    if ($null -eq $script:LateralityCodesCache -or $null -eq $script:LateralityCodesCacheTime -or $latFileTime -gt $script:LateralityCodesCacheTime) {
        if ($useLatJson) {
            Write-Host "Loading Laterality.json..." -ForegroundColor Cyan
            $script:LateralityCodesCache = Read-LateralityJson $latJson
            $sourceType += "JSON"
        } else {
            Write-Host "Loading Laterality.xlsx..." -ForegroundColor Cyan
            $script:LateralityCodesCache = Read-LateralityExcel $latXlsx
            $sourceType += "Excel"
        }
        $script:LateralityCodesCacheTime = $latFileTime
        $needsReload = $true
    }
    
    $loadStopwatch.Stop()
    
    if ($needsReload) {
        $sourceInfo = if ($sourceType -contains "JSON") { " (using JSON)" } else { " (using Excel)" }
        Write-Host ("Loaded {0} topography rules, {1} melanoma rules, {2} laterality codes in {3:F2} seconds{4}." -f 
            $script:TopoMapCache.Count, $script:MelTopoMapCache.Count, $script:LateralityCodesCache.Count, 
            $loadStopwatch.Elapsed.TotalSeconds, $sourceInfo) -ForegroundColor Cyan
    } else {
        Write-Host ("Using cached maps: {0} topography rules, {1} melanoma rules, {2} laterality codes (checked in {3:F3} seconds)." -f 
            $script:TopoMapCache.Count, $script:MelTopoMapCache.Count, $script:LateralityCodesCache.Count, 
            $loadStopwatch.Elapsed.TotalSeconds) -ForegroundColor Green
    }
    
    return @{
        TopoMap = $script:TopoMapCache
        MelTopoMap = $script:MelTopoMapCache
        LateralityCodes = $script:LateralityCodesCache
    }
}

function Get-MissingFields {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )

    $scriptDir = $PSScriptRoot

    # Load maps (with caching)
    $maps = Get-CachedMaps -ScriptDir $scriptDir
    $topoMap = $maps.TopoMap
    $melTopoMap = $maps.MelTopoMap
    $lateralityCodes = $maps.LateralityCodes

    $report = @()
    $assignments = @{}
    
    Write-Host "Processing $($Tumors.Count) tumors..." -ForegroundColor Cyan
    $processStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 0; $i -lt $Tumors.Count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

        # Get patient name for display
        $nameLast = ""
        $nameFirst = ""
        if ($patient -ne $null) {
            $nameLast = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameLast"
            $nameFirst = Get-ItemValue -Context $patient -NsMgr $NsMgr -Id "nameFirst"
        }
        $patientName = "$nameLast, $nameFirst".Trim(', ')

        # Get current values
        $currentSite = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "primarySite").Trim()
        $currentLat = (Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "laterality").Trim()

        # Skip if both site and laterality already exist
        $hasSite = -not [string]::IsNullOrWhiteSpace($currentSite)
        $hasLat = -not [string]::IsNullOrWhiteSpace($currentLat)
        
        if ($hasSite -and $hasLat) {
            continue
        }

        $proposedSite = ""
        $proposedLat = ""
        $sourceText = ""
        $textCombined = ""

        # Get text fields
        $textPath = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcPath"
        $textPe   = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcPe"
        $textLab  = Get-ItemValue -Context $tumor -NsMgr $NsMgr -Id "textDxProcLabTests"

        # Prefer path + PE text; if both empty, fall back to lab tests
        $textCombined = (($textPath + " " + $textPe)).Trim()
        if (-not $textCombined) {
            $textCombined = $textLab.Trim()
        }

        if (-not $textCombined) {
            continue
        }

        $low = $textCombined.ToLower()

        # Assign primary site if missing
        if (-not $hasSite) {
            # Check for histology-based overrides first
            # Invasive ductal carcinoma -> Breast
            if ($low -match '\binvasive ductal carcinoma\b') {
                $proposedSite = "C509"
            }
            # Renal cell carcinoma -> Kidney
            elseif ($low -match '\brenal cell carcinoma\b') {
                $proposedSite = "C649"
            }
            # Prostate indicators -> Prostate
            elseif ($low -match '\b(prostatectomy|prostatic adenocarcinoma|gleason)\b') {
                $proposedSite = "C619"
            }
            # Bone marrow override (must check before general bone)
            elseif ($low -match '\bbone marrow\b') {
                $proposedSite = "C421"
            }
            else {
                # Standard topography lookup
                $hasMel = $low.Contains("melanoma")

                if ($hasMel) {
                    $proposedSite = Get-BestCode $melTopoMap $low
                    if ($proposedSite -eq "") { $proposedSite = "C449" }
                }
                else {
                    $proposedSite = Get-BestCode $topoMap $low
                }
            }
        }

        # Determine which site to use for laterality check
        $siteToCheck = if ($proposedSite) { $proposedSite } else { $currentSite }

        # Assign laterality if missing and site requires it
        if (-not $hasLat -and $siteToCheck) {
            # Check if this site is in the laterality table
            if ($lateralityCodes.ContainsKey($siteToCheck)) {
                # Site can take laterality codes 1, 2, 5, or 9
                $detectedLat = Get-Laterality $low
                if ($detectedLat) {
                    # We found "left" or "right" in the text
                    $proposedLat = $detectedLat
                }
                else {
                    # No left/right found, assign "unknown" (9)
                    $proposedLat = "9"
                }
            }
            else {
                # Site NOT in laterality table - assign 0 (not coded)
                $proposedLat = "0"
            }
        }

        # Get source text snippet (first 200 chars of combined text)
        if ($proposedSite -or $proposedLat) {
            $sourceText = $textCombined
            if ($sourceText.Length -gt 200) {
                $sourceText = $sourceText.Substring(0, 200) + "..."
            }
        }

        # Create report entry if we have any proposed changes
        if ($proposedSite -or $proposedLat) {
            $report += [PSCustomObject]@{
                TumorIndex         = $i + 1
                PatientName        = $patientName
                CurrentSite        = $currentSite
                ProposedSite       = if ($proposedSite) { $proposedSite } else { "" }
                CurrentLaterality  = $currentLat
                ProposedLaterality = if ($proposedLat) { $proposedLat } else { "" }
                SourceText         = $sourceText
            }

            $assignments[$i] = @{
                PrimarySite = $proposedSite
                Laterality  = $proposedLat
            }
        }
    }
    
    $processStopwatch.Stop()
    Write-Host ("Processed {0} tumors in {1:F2} seconds ({2:F3} seconds per tumor)." -f $Tumors.Count, $processStopwatch.Elapsed.TotalSeconds, ($processStopwatch.Elapsed.TotalSeconds / $Tumors.Count)) -ForegroundColor Cyan

    return @{
        Report = $report
        Assignments = $assignments
    }
}

function Write-AssignedXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors,
        [hashtable]$Assignments,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath
    )

    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null

    # Copy XML declaration
    $declNode = $XmlDoc.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlDeclaration] } |
        Select-Object -First 1
    if ($declNode) {
        $newDecl = $newDoc.CreateXmlDeclaration($declNode.Version, $declNode.Encoding, $declNode.Standalone)
        [void]$newDoc.AppendChild($newDecl)
    }

    # Copy root element
    $root    = $XmlDoc.DocumentElement
    $newRoot = $newDoc.CreateElement($root.Prefix, $root.LocalName, $root.NamespaceURI)
    foreach ($attr in $root.Attributes) {
        $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
        $newAttr.Value = $attr.Value
        [void]$newRoot.Attributes.Append($newAttr)
    }
    [void]$newDoc.AppendChild($newRoot)

    # Copy non-Patient children of root
    foreach ($child in $root.ChildNodes) {
        if ($child.LocalName -ne "Patient") {
            $imported = $newDoc.ImportNode($child, $true)
            [void]$newRoot.AppendChild($imported)
        }
    }

    # Process each Patient
    foreach ($patientNode in $root.SelectNodes("./n:Patient", $NsMgr)) {
        $newPatient = $newDoc.CreateElement($patientNode.Prefix, $patientNode.LocalName, $patientNode.NamespaceURI)

        # Copy patient attributes
        foreach ($attr in $patientNode.Attributes) {
            $newAttr       = $newDoc.CreateAttribute($attr.Prefix, $attr.LocalName, $attr.NamespaceURI)
            $newAttr.Value = $attr.Value
            [void]$newPatient.Attributes.Append($newAttr)
        }

        # Copy patient-level Items
        foreach ($child in $patientNode.ChildNodes) {
            if ($child.LocalName -eq "Item") {
                $imported = $newDoc.ImportNode($child, $true)
                [void]$newPatient.AppendChild($imported)
            }
        }

        # Process tumors
        $tumorsInPatient = $patientNode.SelectNodes("./n:Tumor", $NsMgr)
        
        foreach ($tumor in $tumorsInPatient) {
            # Find this tumor's index in the global list
            $tumorIndex = -1
            for ($i = 0; $i -lt $Tumors.Count; $i++) {
                if ($Tumors[$i] -eq $tumor) {
                    $tumorIndex = $i
                    break
                }
            }

            # Clone the tumor
            $newTumor = $newDoc.ImportNode($tumor, $true)

            # Apply assignments if this tumor has them
            if ($tumorIndex -ge 0 -and $Assignments.ContainsKey($tumorIndex)) {
                $assignment = $Assignments[$tumorIndex]
                
                # Set primary site if proposed
                if ($assignment.PrimarySite) {
                    $siteNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='primarySite']", $NsMgr)
                    if ($siteNode) {
                        $siteNode.InnerText = $assignment.PrimarySite
                    }
                    else {
                        # Create new Item element
                        $siteNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                        $attr = $newDoc.CreateAttribute("naaccrId")
                        $attr.Value = "primarySite"
                        [void]$siteNode.Attributes.Append($attr)
                        $siteNode.InnerText = $assignment.PrimarySite
                        [void]$newTumor.AppendChild($siteNode)
                    }
                }

                # Set laterality if proposed
                if ($assignment.Laterality) {
                    $latNode = $newTumor.SelectSingleNode("./n:Item[@naaccrId='laterality']", $NsMgr)
                    if ($latNode) {
                        $latNode.InnerText = $assignment.Laterality
                    }
                    else {
                        # Create new Item element
                        $latNode = $newDoc.CreateElement("Item", $root.NamespaceURI)
                        $attr = $newDoc.CreateAttribute("naaccrId")
                        $attr.Value = "laterality"
                        [void]$latNode.Attributes.Append($attr)
                        $latNode.InnerText = $assignment.Laterality
                        [void]$newTumor.AppendChild($latNode)
                    }
                }
            }

            [void]$newPatient.AppendChild($newTumor)
        }

        [void]$newRoot.AppendChild($newPatient)
    }

    # Save with formatting
    $settings                = New-Object System.Xml.XmlWriterSettings
    $settings.Indent         = $true
    $settings.NewLineChars   = "`r`n"
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Show-AssignmentReport {
    param(
        [array]$Report,
        [hashtable]$Assignments,
        [string]$OriginalFilePath,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNodeList]$Tumors
    )

    # Count assignments
    $siteCount = 0
    $latCount = 0
    foreach ($assignment in $Assignments.Values) {
        if ($assignment.PrimarySite) { $siteCount++ }
        if ($assignment.Laterality) { $latCount++ }
    }

    $reportForm = New-Object System.Windows.Forms.Form
    $reportForm.Text = "Primary Site & Laterality Assignment Report"
    $reportForm.Width = 1600
    $reportForm.Height = 800
    $reportForm.StartPosition = "CenterScreen"

    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 40)
    $lblSummary.Text = "Tumors to update: $($Assignments.Count) | Sites to assign: $siteCount | Lateralities to assign: $latCount"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # Split container for grid and text preview
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Location = New-Object System.Drawing.Point(10, 60)
    $splitContainer.Size = New-Object System.Drawing.Size(1560, 630)
    $splitContainer.Anchor = 'Top,Left,Right,Bottom'
    $splitContainer.Orientation = 'Horizontal'
    $splitContainer.SplitterDistance = 300

    # DataGridView for report (top)
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = "AllCells"
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false

    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("TumorIndex", [int])
    [void]$table.Columns.Add("PatientName", [string])
    [void]$table.Columns.Add("CurrentSite", [string])
    [void]$table.Columns.Add("ProposedSite", [string])
    [void]$table.Columns.Add("CurrentLaterality", [string])
    [void]$table.Columns.Add("ProposedLaterality", [string])
    [void]$table.Columns.Add("SourceText", [string])

    foreach ($item in $Report) {
        $row = $table.NewRow()
        $row["TumorIndex"] = $item.TumorIndex
        $row["PatientName"] = $item.PatientName
        $row["CurrentSite"] = $item.CurrentSite
        $row["ProposedSite"] = $item.ProposedSite
        $row["CurrentLaterality"] = $item.CurrentLaterality
        $row["ProposedLaterality"] = $item.ProposedLaterality
        $row["SourceText"] = $item.SourceText
        [void]$table.Rows.Add($row)
    }

    $grid.DataSource = $table

    # RichTextBox for text field preview (bottom)
    $rtbPreview = New-Object System.Windows.Forms.RichTextBox
    $rtbPreview.Dock = 'Fill'
    $rtbPreview.ReadOnly = $true
    $rtbPreview.Font = New-Object System.Drawing.Font("Consolas", 9)
    $rtbPreview.WordWrap = $true

    # Add to split container
    $splitContainer.Panel1.Controls.Add($grid)
    $splitContainer.Panel2.Controls.Add($rtbPreview)

    # Buttons
    $btnSaveXml = New-Object System.Windows.Forms.Button
    $btnSaveXml.Text = "Save Assigned XML"
    $btnSaveXml.Width = 150
    $btnSaveXml.Location = New-Object System.Drawing.Point(10, 710)
    $btnSaveXml.Anchor = 'Bottom,Left'

    $btnSaveCsv = New-Object System.Windows.Forms.Button
    $btnSaveCsv.Text = "Save CSV Report"
    $btnSaveCsv.Width = 150
    $btnSaveCsv.Location = New-Object System.Drawing.Point(170, 710)
    $btnSaveCsv.Anchor = 'Bottom,Left'

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(330, 710)
    $btnClose.Anchor = 'Bottom,Left'

    # Grid selection handler - show text fields
    $grid.Add_SelectionChanged({
        if ($grid.SelectedRows.Count -eq 0) { return }
        
        $selectedRow = $grid.SelectedRows[0]
        $tumorIndex = [int]$selectedRow.Cells["TumorIndex"].Value - 1

        if ($tumorIndex -lt 0 -or $tumorIndex -ge $Tumors.Count) { return }

        $tumor = $Tumors[$tumorIndex]
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
        $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

        $rtbPreview.Clear()

        # Show text fields
        $textFieldIds = @(
            "textDxProcLabTests",
            "textDxProcPath",
            "textDxProcPe",
            "textHistologyTitle",
            "textPrimarySiteTitle"
        )

        foreach ($textId in $textFieldIds) {
            $node = $tumor.SelectSingleNode("./n:Item[@naaccrId='$textId']", $nsMgr)
            if ($node -ne $null) {
                $rtbPreview.SelectionFont = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
                $rtbPreview.AppendText("=== $textId ===`r`n")
                $rtbPreview.SelectionFont = New-Object System.Drawing.Font("Consolas", 9)

                $value = $node.InnerText
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $rtbPreview.AppendText("(no text)`r`n")
                }
                else {
                    $rtbPreview.AppendText("$value`r`n")
                }

                $rtbPreview.AppendText("`r`n")
            }
        }
    })

    # Save XML button handler
    $btnSaveXml.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $outputPath = [System.IO.Path]::Combine($directory, "$originalFileName-assigned.xml")

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
            $nsMgr.AddNamespace("n", $XmlDoc.DocumentElement.NamespaceURI)

            Write-AssignedXml -XmlDoc $XmlDoc -Tumors $Tumors -Assignments $Assignments -NsMgr $nsMgr -OutputPath $outputPath

            [System.Windows.Forms.MessageBox]::Show(
                "Assigned XML saved to:`n$outputPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving XML: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Save CSV button handler
    $btnSaveCsv.Add_Click({
        try {
            $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFilePath)
            $directory = [System.IO.Path]::GetDirectoryName($OriginalFilePath)
            $csvPath = [System.IO.Path]::Combine($directory, "$originalFileName-assignment-report.csv")

            $Report | Export-Csv -Path $csvPath -NoTypeInformation

            [System.Windows.Forms.MessageBox]::Show(
                "CSV report saved to:`n$csvPath",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving CSV: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Close button handler
    $btnClose.Add_Click({
        $reportForm.Close()
    })

    # Add controls to form
    $reportForm.Controls.AddRange(@($lblSummary, $splitContainer, $btnSaveXml, $btnSaveCsv, $btnClose))

    [void]$reportForm.ShowDialog()
}