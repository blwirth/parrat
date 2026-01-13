function Get-NaaccrItemMap {
    param(
        [int]$Index
    )

    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        throw "Get-NaaccrItemMap: script:Tumors is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Tumors.Count) {
        throw "Get-NaaccrItemMap: Index $Index is out of range (0..$($script:Tumors.Count - 1))."
    }

    $tumor   = $script:Tumors[$Index]
    $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $script:NsMgr)

    $map = @{}

    # Patient items
    if ($patient -ne $null) {
        $pItems = $patient.SelectNodes("./n:Item", $script:NsMgr)
        foreach ($item in $pItems) {
            $id  = $item.GetAttribute("naaccrId")
            $val = $item.InnerText
            $map["P|$id"] = $val
        }
    }

    # Tumor items
    $tItems = $tumor.SelectNodes("./n:Item", $script:NsMgr)
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
        $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']",  $script:NsMgr)
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
        [int]$IndexA,
        [int]$IndexB
    )

    if (-not $script:Tumors -or $script:Tumors.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No tumors loaded.", "Diff")
        return
    }

    if ($IndexA -lt 0 -or $IndexA -ge $script:Tumors.Count -or
        $IndexB -lt 0 -or $IndexB -ge $script:Tumors.Count) {
        [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
        return
    }

    $mapA = Get-NaaccrItemMap -Index $IndexA
    $mapB = Get-NaaccrItemMap -Index $IndexB

    # Combined key set
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $mapA.Keys) { [void]$keys.Add($k) }
    foreach ($k in $mapB.Keys) { [void]$keys.Add($k) }

    # Build DataTable for diff
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Scope",    [string])
    [void]$table.Columns.Add("naaccrId", [string])
    [void]$table.Columns.Add("ValueA",   [string])
    [void]$table.Columns.Add("ValueB",   [string])
    [void]$table.Columns.Add("Status",   [string])

    foreach ($k in $keys) {
        $parts     = $k.Split('|', 2)
        $scopeCode = $parts[0]
        $id        = $parts[1]

        $scope = if ($scopeCode -eq "P") { "Patient" } else { "Tumor" }

        $hasA = $mapA.ContainsKey($k)
        $hasB = $mapB.ContainsKey($k)

        $valA = if ($hasA) { $mapA[$k] } else { "" }
        $valB = if ($hasB) { $mapB[$k] } else { "" }

        if (-not $hasA -and -not $hasB) { continue }

        if     ($hasA -and $hasB -and $valA -eq $valB) { $status = "Same" }
        elseif ($hasA -and $hasB)                      { $status = "Different" }
        elseif ($hasA)                                 { $status = "Only A" }
        else                                           { $status = "Only B" }

        $row = $table.NewRow()
        $row["Scope"]    = $scope
        $row["naaccrId"] = $id
        $row["ValueA"]   = $valA
        $row["ValueB"]   = $valB
        $row["Status"]   = $status
        [void]$table.Rows.Add($row)
    }

    $labelA = Get-TumorLabel -Index $IndexA
    $labelB = Get-TumorLabel -Index $IndexB

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text          = "Diff: $labelA  VS  $labelB"
    $diffForm.Width         = 1600
    $diffForm.Height        = 800
    $diffForm.StartPosition = "CenterScreen"

    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Dock                  = 'Fill'
    $gridDiff.ReadOnly              = $true
    $gridDiff.AutoSizeColumnsMode   = "Fill"
    $gridDiff.RowHeadersVisible     = $false
    $gridDiff.AllowUserToAddRows    = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.DataSource            = $table

    $gridDiff.add_RowPrePaint({
        param($sender, $e)
        $row    = $sender.Rows[$e.RowIndex]
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

# ============================================================================
# HL7 Diff Functions
# ============================================================================

function Get-Hl7FieldMap {
    param(
        [int]$Index
    )

    if (-not $script:Hl7Messages -or $script:Hl7Messages.Count -eq 0) {
        throw "Get-Hl7FieldMap: script:Hl7Messages is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Hl7Messages.Count) {
        throw "Get-Hl7FieldMap: Index $Index is out of range (0..$($script:Hl7Messages.Count - 1))."
    }

    $message = $script:Hl7Messages[$Index]
    $map = @{}

    # Iterate through all segment types in the message
    foreach ($segType in $message.Segments.Keys) {
        $segments = $message.Segments[$segType]
        $instanceNum = 1

        foreach ($segment in $segments) {
            # Split segment into fields by pipe delimiter
            $fields = $segment -split '\|'
            
            # For MSH segment, field numbering is special:
            # MSH-1 is the field separator (|) itself
            # MSH-2 is the encoding characters (^~\&)
            # So fields[0] = "MSH", fields[1] = "^~\&" (which is MSH-2)
            
            $fieldOffset = 0
            if ($segType -eq "MSH") {
                # MSH segment: fields[0]="MSH", fields[1]=encoding chars (MSH-2)
                # So fields[1] corresponds to MSH-2, fields[2] to MSH-3, etc.
                $fieldOffset = 1
            }

            for ($i = 1; $i -lt $fields.Count; $i++) {
                $fieldValue = $fields[$i]
                
                # Skip empty fields to reduce noise
                if ([string]::IsNullOrWhiteSpace($fieldValue)) {
                    continue
                }

                # Calculate field number
                $fieldNum = $i + $fieldOffset

                # Key format: SegmentType[Instance].FieldNumber
                $key = "{0}[{1}].{2}" -f $segType, $instanceNum, $fieldNum
                $map[$key] = $fieldValue
            }

            $instanceNum++
        }
    }

    return $map
}

function Get-Hl7MessageLabel {
    param(
        [int]$Index
    )

    if (-not $script:Hl7Messages -or $script:Hl7Messages.Count -eq 0) {
        throw "Get-Hl7MessageLabel: script:Hl7Messages is null or empty."
    }
    if ($Index -lt 0 -or $Index -ge $script:Hl7Messages.Count) {
        throw "Get-Hl7MessageLabel: Index $Index is out of range (0..$($script:Hl7Messages.Count - 1))."
    }

    $message = $script:Hl7Messages[$Index]

    $patientName = $message.PatientName
    $messageType = $message.MessageType
    $patientId   = $message.PatientId

    return "Idx {0} - {1} ({2}) - ID: {3}" -f ($Index + 1), $patientName, $messageType, $patientId
}

function Show-Hl7MessageDiff {
    param(
        [int]$IndexA,
        [int]$IndexB
    )

    if (-not $script:Hl7Messages -or $script:Hl7Messages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No HL7 messages loaded.", "Diff")
        return
    }

    if ($IndexA -lt 0 -or $IndexA -ge $script:Hl7Messages.Count -or
        $IndexB -lt 0 -or $IndexB -ge $script:Hl7Messages.Count) {
        [System.Windows.Forms.MessageBox]::Show("Selected indices are out of range.", "Diff")
        return
    }

    $mapA = Get-Hl7FieldMap -Index $IndexA
    $mapB = Get-Hl7FieldMap -Index $IndexB

    # Combined key set
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $mapA.Keys) { [void]$keys.Add($k) }
    foreach ($k in $mapB.Keys) { [void]$keys.Add($k) }

    # Build DataTable for diff
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Segment",  [string])
    [void]$table.Columns.Add("Field#",   [string])
    [void]$table.Columns.Add("ValueA",   [string])
    [void]$table.Columns.Add("ValueB",   [string])
    [void]$table.Columns.Add("Status",   [string])

    # Sort keys for consistent display (by segment type, then instance, then field number)
    $sortedKeys = $keys | Sort-Object {
        # Parse key format: SegmentType[Instance].FieldNumber
        if ($_ -match '^([A-Z]{2,3})\[(\d+)\]\.(\d+)$') {
            $segType = $matches[1]
            $instance = [int]$matches[2]
            $fieldNum = [int]$matches[3]
            # Return sortable tuple: segment name, instance, field number
            return "{0}_{1:D4}_{2:D4}" -f $segType, $instance, $fieldNum
        }
        return $_
    }

    foreach ($k in $sortedKeys) {
        # Parse the key to extract segment and field info
        $segment = $k
        $fieldNum = ""
        
        if ($k -match '^([A-Z]{2,3}\[\d+\])\.(\d+)$') {
            $segment = $matches[1]
            $fieldNum = $matches[2]
        }

        $hasA = $mapA.ContainsKey($k)
        $hasB = $mapB.ContainsKey($k)

        $valA = if ($hasA) { $mapA[$k] } else { "" }
        $valB = if ($hasB) { $mapB[$k] } else { "" }

        if (-not $hasA -and -not $hasB) { continue }

        if     ($hasA -and $hasB -and $valA -eq $valB) { $status = "Same" }
        elseif ($hasA -and $hasB)                      { $status = "Different" }
        elseif ($hasA)                                 { $status = "Only A" }
        else                                           { $status = "Only B" }

        $row = $table.NewRow()
        $row["Segment"]  = $segment
        $row["Field#"]   = $fieldNum
        $row["ValueA"]   = $valA
        $row["ValueB"]   = $valB
        $row["Status"]   = $status
        [void]$table.Rows.Add($row)
    }

    $labelA = Get-Hl7MessageLabel -Index $IndexA
    $labelB = Get-Hl7MessageLabel -Index $IndexB

    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text          = "HL7 Diff: $labelA  VS  $labelB"
    $diffForm.Width         = 1600
    $diffForm.Height        = 800
    $diffForm.StartPosition = "CenterScreen"

    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Dock                  = 'Fill'
    $gridDiff.ReadOnly              = $true
    $gridDiff.RowHeadersVisible     = $false
    $gridDiff.AllowUserToAddRows    = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.DataSource            = $table

    # Set column widths - all columns are manually resizable
    # Columns: 0=Segment, 1=Field#, 2=ValueA, 3=ValueB, 4=Status
    $gridDiff.Columns[0].Width = 120
    $gridDiff.Columns[1].Width = 60
    $gridDiff.Columns[2].Width = 500
    $gridDiff.Columns[3].Width = 500
    $gridDiff.Columns[4].Width = 80

    $gridDiff.add_RowPrePaint({
        param($sender, $e)
        $row    = $sender.Rows[$e.RowIndex]
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