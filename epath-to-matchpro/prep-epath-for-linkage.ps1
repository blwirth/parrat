# cd into dir where script is
# .\[script-name] -InputFile "[filepath]"
# The inputfile MUST have a facility number for the RepHosp to be assigned.
# Will output a file in the same dir as input file

param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,
    [string]$OutputFile # optional
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$TopoXlsx    = Join-Path $ScriptDir "Topography.xlsx"
$MelTopoXlsx = Join-Path $ScriptDir "TopographyMelanoma.xlsx"

if (-not (Test-Path $TopoXlsx)) {
    throw "Missing Topography.xlsx in script folder: $ScriptDir"
}
if (-not (Test-Path $MelTopoXlsx)) {
    throw "Missing TopographyMelanoma.xlsx in script folder: $ScriptDir"
}
if (-not (Test-Path $InputFile)) {
    throw "Input NAACCR XML file not found: $InputFile"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $dir  = [System.IO.Path]::GetDirectoryName($InputFile)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $ext  = [System.IO.Path]::GetExtension($InputFile)
    if ([string]::IsNullOrWhiteSpace($ext)) {
        $ext = ".xml"
    }
	# mp for match pro
    $OutputFile = Join-Path $dir ("{0}_mp{1}" -f $name, $ext)
}

# Get facility number from filename and pad to 10 digits
# Will probably need to account for potential 8-digit dates and exclude these
# or just don't put a date in the filename
$baseFile = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
$facilityMatch = [regex]::Match($baseFile, '\d{6,10}')
if (-not $facilityMatch.Success) {
    throw "Could not find a 6- to 10-digit facility number in file name '$baseFile'."
}
$repHosp = $facilityMatch.Value.PadLeft(10, '0')
Write-Host "reportingFacility set to $repHosp" -ForegroundColor Green


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

Write-Host "Loading topography tables..." -ForegroundColor Cyan

$topoMap = Read-TopographyExcel $TopoXlsx |
    Where-Object { $_.Code -and $_.SearchPhrase -and $_.Code -notlike 'C77?' }

$melTopoMap = Read-TopographyExcel $MelTopoXlsx |
    Where-Object { $_.Code -and $_.SearchPhrase }

Write-Host ("Loaded {0} topography rules, {1} melanoma rules." -f $topoMap.Count, $melTopoMap.Count) -ForegroundColor Cyan

$xml = [System.Xml.XmlDocument]::new()
$xml.XmlResolver = $null
$xml.PreserveWhitespace = $true
$xml.Load($InputFile)

function Get-ItemNode {
    param($Context, $Id)
    $Context.SelectSingleNode(".//*[local-name()='Item' and @naaccrId='$Id']")
}

function Get-ItemValue {
    param($Context,$Id)
    $n = Get-ItemNode -Context $Context -Id $Id
    if ($n) { return $n.InnerText } else { return "" }
}

function Set-ItemValue {
    param(
        $Context,
        [string]$Id,
        [string]$Value
    )

    $doc  = $Context.OwnerDocument
    if (-not $doc) { $doc = $Context }

    $item = Get-ItemNode -Context $Context -Id $Id

    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($item) { $item.InnerText = "" }
        return
    }

    if (-not $item) {
        $ns   = $doc.DocumentElement.NamespaceURI
        $last = $Context.LastChild

        if ($last -and $last.NodeType -eq [System.Xml.XmlNodeType]::Text) {
            $last.Value = "`r`n      "
        }
        else {
           # $Context.AppendChild($doc.CreateTextNode("`r`n      ")) | Out-Null
        }

        $item = $doc.CreateElement("Item", $ns)
        $attr = $doc.CreateAttribute("naaccrId")
        $attr.Value = $Id
        [void]$item.Attributes.Append($attr)

        [void]$Context.AppendChild($item)

        $Context.AppendChild($doc.CreateTextNode("`r`n      ")) | Out-Null
    }

    $item.InnerText = $Value
}

function Get-BestCode {
    param($Map,$TextLow)

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

    $pLeft  = $TextLow.IndexOf("left")
    $pRight = $TextLow.IndexOf("right")

    if ($pLeft -lt 0 -and $pRight -lt 0) { return "" }
    if ($pLeft -ge 0 -and ($pRight -lt 0 -or $pLeft -lt $pRight)) { return "2" }
    return "1"
}

function Apply-Laterality {
    param($Tumor, $TextLow)

    $latNode = Get-ItemNode -Context $Tumor -Id "laterality"
    if ($latNode -and -not [string]::IsNullOrWhiteSpace($latNode.InnerText)) {
        return
    }

    $site = Get-ItemValue $Tumor "primarySite"
    if ([string]::IsNullOrWhiteSpace($site)) { return }

    if ($site -eq "C449") {
        Set-ItemValue $Tumor "laterality" "0"
        return
    }

    $prefix = $site.Substring(0,3)

    $needsLat =
        ($prefix -eq "C44") -or
        ($prefix -eq "C50") -or
        ($prefix -eq "C34") -or
        ($site   -eq "C649") -or
        ($site   -eq "C569")

    if (-not $needsLat) { return }

    $lat = Get-Laterality $TextLow
    if ([string]::IsNullOrEmpty($lat)) { return }

    Set-ItemValue $Tumor "laterality" $lat
}

$tumors    = $xml.SelectNodes("//*[local-name()='Tumor']")
$processed = 0
$updated   = 0

foreach ($tumor in $tumors) {
    $processed++

    # Set reportingFacility from filename IF existing value is all zeros
    $rfCurrent = (Get-ItemValue $tumor "reportingFacility").Trim()
    if ($rfCurrent -and $rfCurrent -match '^[0]+$') {
        Set-ItemValue $tumor "reportingFacility" $repHosp
    }

    # ONLY assign primarySite when it is missing/blank
    $existingSite = (Get-ItemValue $tumor "primarySite").Trim()
    if ($existingSite) {
        continue
    }

	$textPath = Get-ItemValue $tumor "textDxProcPath"
	$textPe   = Get-ItemValue $tumor "textDxProcPe"
	$textLab  = Get-ItemValue $tumor "textDxProcLabTests"

	# Prefer path + PE text; if both empty, fall back to lab tests (see Concord files for this issue)
	$textCombined = (($textPath + " " + $textPe)).Trim()
	if (-not $textCombined) {
		$textCombined = $textLab.Trim()
	}

	if (-not $textCombined) { continue }

	$low = $textCombined.ToLower()

    $hasMel = $low.Contains("melanoma")

    $code = ""

    if ($hasMel) {
        $code = Get-BestCode $melTopoMap $low
        if ($code -eq "") { $code = "C449" }
    }
    else {
        $code = Get-BestCode $topoMap $low
    }

    if ($code -ne "") {
        Set-ItemValue $tumor "primarySite" $code
        $updated++
        Apply-Laterality $tumor $low
    }
}

$xml.Save($OutputFile)

# Final stats on primarySite
$withPrimary    = 0
$withoutPrimary = 0

foreach ($tumor in $tumors) {
    $site = (Get-ItemValue $tumor "primarySite").Trim()
    if ($site) {
        $withPrimary++
    } else {
        $withoutPrimary++
    }
}

Write-Host "Tumors processed              : $processed" -ForegroundColor Cyan
Write-Host "Tumors updated (primarySite)  : $updated"   -ForegroundColor Cyan
Write-Host "Tumors with primarySite       : $withPrimary"    -ForegroundColor Green
Write-Host "Tumors with no primarySite    : $withoutPrimary" -ForegroundColor Yellow
Write-Host "Output: $OutputFile" -ForegroundColor Green
