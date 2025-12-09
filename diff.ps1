# NaaccrDiff.ps1
# Utilities for comparing two tumors from a NAACCR XML document.

function Get-NaaccrItemMap {
    param(
        [System.Xml.XmlNode[]]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [int]$Index
    )

    $tumor = $Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

    $map = @{}

    # Patient items
    if ($patient -ne $null) {
        $pItems = $patient.SelectNodes("./n:Item", $NsMgr)
        foreach ($item in $pItems) {
            $id  = $item.GetAttribute("naaccrId")
            $val = $item.InnerText
            $map["P|$id"] = $val
        }
    }

    # Tumor items
    $tItems = $tumor.SelectNodes("./n:Item", $NsMgr)
    foreach ($item in $tItems) {
        $id  = $item.GetAttribute("naaccrId")
        $val = $item.InnerText
        $map["T|$id"] = $val
    }

    return $map
}

function Get-TumorLabel {
    param(
        [int]$Index
    )

    # Use script-scope state
    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        throw "Get-TumorLabel: script:Tumors is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
        throw "Get-TumorLabel: Index $Index is out of range (0..$($script:Tumors.Count - 1))."
    }

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $nameLast          = ""
    $nameFirst         = ""
    $dxDate            = ""
	$pathReportNumber1 = ""

    if ($patient -ne $null) {
        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $script:NsMgr)
        $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $script:NsMgr)
        if ($nlNode) { $nameLast  = $nlNode.InnerText }
        if ($nfNode) { $nameFirst = $nfNode.InnerText }
    }

    $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $script:NsMgr)
    if ($dxNode) { $dxDate = $dxNode.InnerText }
	
	$dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $script:NsMgr)
    if ($dxNode) { $pathReportNumber1 = $dxNode.InnerText }

    return "Idx {0} - {1}, {2} - Dx {3} - Path Number {4}" -f ($Index + 1), $nameLast, $nameFirst, $dxDate, $pathReportNumber1
}

function Show-NaaccrTumorDiff {
    param(
        [System.Xml.XmlNode[]]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [int]$IndexA,
        [int]$IndexB
    )

    $mapA = Get-NaaccrItemMap -Tumors $Tumors -NsMgr $NsMgr -Index $IndexA
    $mapB = Get-NaaccrItemMap -Tumors $Tumors -NsMgr $NsMgr -Index $IndexB

    # Combined key set
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $mapA.Keys) { [void]$keys.Add($k) }
    foreach ($k in $mapB.Keys) { [void]$keys.Add($k) }

    # Build DataTable for diff
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Scope",   [string]) # Patient/Tumor
    [void]$table.Columns.Add("naaccrId",[string])
    [void]$table.Columns.Add("ValueA",  [string])
    [void]$table.Columns.Add("ValueB",  [string])
    [void]$table.Columns.Add("Status",  [string]) # Same, Different, Only A, Only B

    foreach ($k in $keys) {
        $parts = $k.Split('|', 2)
        $scopeCode = $parts[0]
        $id        = $parts[1]

        $scope = if ($scopeCode -eq "P") { "Patient" } else { "Tumor" }

        $hasA = $mapA.ContainsKey($k)
        $hasB = $mapB.ContainsKey($k)

        $valA = if ($hasA) { $mapA[$k] } else { "" }
        $valB = if ($hasB) { $mapB[$k] } else { "" }

        if (-not $hasA -and -not $hasB) { continue }

        if ($hasA -and $hasB) {
            if ($valA -eq $valB) {
                $status = "Same"
            } else {
                $status = "Different"
            }
        }
        elseif ($hasA) {
            $status = "Only A"
        }
        else {
            $status = "Only B"
        }

        $row = $table.NewRow()
        $row["Scope"]    = $scope
        $row["naaccrId"] = $id
        $row["ValueA"]   = $valA
        $row["ValueB"]   = $valB
        $row["Status"]   = $status
        [void]$table.Rows.Add($row)
    }

    $labelA = Get-TumorLabel -Tumors $Tumors -NsMgr $NsMgr -Index $IndexA
    $labelB = Get-TumorLabel -Tumors $Tumors -NsMgr $NsMgr -Index $IndexB

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text   = "Diff: $labelA  VS  $labelB"
    $diffForm.Width  = 1600
    $diffForm.Height = 800
    $diffForm.StartPosition = "CenterScreen"

    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Dock = 'Fill'
    $gridDiff.ReadOnly = $true
    $gridDiff.AutoSizeColumnsMode = "Fill"
    $gridDiff.RowHeadersVisible = $false
    $gridDiff.AllowUserToAddRows = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.DataSource = $table

    # Color rows by Status
    $gridDiff.add_RowPrePaint({
        param($sender, $e)
        $row = $sender.Rows[$e.RowIndex]
        $status = [string]$row.Cells["Status"].Value
        switch ($status) {
            "Same"      { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White }
            "Different" { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow }
            "Only A"    { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightBlue }
            "Only B"    { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen }
        }
    })

    $diffForm.Controls.Add($gridDiff)
    [void]$diffForm.ShowDialog()
}
