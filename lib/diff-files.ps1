# diff-files.ps1
# File-level diff for NAACCR XML files

function Show-FileDiff {
    <#
    .SYNOPSIS
    Opens file picker to select two NAACCR XML files and displays a side-by-side diff.
    #>
    
    # File picker for first file
    $openFileDialog1 = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog1.Filter = "NAACCR XML Files (*.xml)|*.xml"
    $openFileDialog1.Title = "Select First XML File"
    $openFileDialog1.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
    
    if ($openFileDialog1.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    
    $filePathA = $openFileDialog1.FileName
    
    # File picker for second file
    $openFileDialog2 = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog2.Filter = "NAACCR XML Files (*.xml)|*.xml"
    $openFileDialog2.Title = "Select Second XML File"
    $openFileDialog2.InitialDirectory = [System.IO.Path]::GetDirectoryName($filePathA)
    
    if ($openFileDialog2.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    
    $filePathB = $openFileDialog2.FileName
    
    # Validate files exist
    if (-not (Test-Path $filePathA)) {
        [System.Windows.Forms.MessageBox]::Show(
            "First file does not exist: $filePathA",
            "File Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    if (-not (Test-Path $filePathB)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Second file does not exist: $filePathB",
            "File Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    # Check file sizes
    $sizeA = (Get-Item $filePathA).Length
    $sizeB = (Get-Item $filePathB).Length
    $maxSize = 10MB
    
    if ($sizeA -gt $maxSize -or $sizeB -gt $maxSize) {
        $sizeMB_A = [math]::Round($sizeA / 1MB, 2)
        $sizeMB_B = [math]::Round($sizeB / 1MB, 2)
        $result = [System.Windows.Forms.MessageBox]::Show(
            "One or both files are large (File A: ${sizeMB_A}MB, File B: ${sizeMB_B}MB).`n`nThis may take some time to process. Continue?",
            "Large File Warning",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }
    
    # Validate files are NAACCR XML
    $validationA = Test-NaaccrXmlFile -FilePath $filePathA
    if (-not $validationA.IsValid) {
        [System.Windows.Forms.MessageBox]::Show(
            "First file is not a valid NAACCR XML file:`n`n$($validationA.Error)",
            "Invalid File",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    $validationB = Test-NaaccrXmlFile -FilePath $filePathB
    if (-not $validationB.IsValid) {
        [System.Windows.Forms.MessageBox]::Show(
            "Second file is not a valid NAACCR XML file:`n`n$($validationB.Error)",
            "Invalid File",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    # Perform comparison
    try {
        $diffResult = Compare-XmlFiles -FilePathA $filePathA -FilePathB $filePathB
        Show-DiffPreview -DiffResult $diffResult -FilePathA $filePathA -FilePathB $filePathB
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error comparing files:`n`n$($_.Exception.Message)",
            "Comparison Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

function Test-NaaccrXmlFile {
    param(
        [string]$FilePath
    )
    
    # Check if file is empty
    if ((Get-Item $FilePath).Length -eq 0) {
        return @{
            IsValid = $false
            Error = "File is empty"
        }
    }
    
    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($FilePath)
        
        # Check if root element is NaaccrData
        if ($xmlDoc.DocumentElement.LocalName -ne "NaaccrData") {
            return @{
                IsValid = $false
                Error = "Root element is not <NaaccrData>. Found: <$($xmlDoc.DocumentElement.LocalName)>"
            }
        }
        
        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "XML parsing error: $($_.Exception.Message)"
        }
    }
}

function Compare-XmlFiles {
    param(
        [string]$FilePathA,
        [string]$FilePathB
    )
    
    # Load both XML files
    $xmlDocA = New-Object System.Xml.XmlDocument
    $xmlDocA.Load($FilePathA)
    
    $xmlDocB = New-Object System.Xml.XmlDocument
    $xmlDocB.Load($FilePathB)
    
    # Create namespace manager
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDocA.NameTable)
    $nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml")
    
    # Get all patients from both files
    $patientsA = $xmlDocA.SelectNodes("//n:Patient", $nsMgr)
    $patientsB = $xmlDocB.SelectNodes("//n:Patient", $nsMgr)
    
    # Build patient maps indexed by patientIdNumber
    $mapA = @{}
    $mapB = @{}
    
    foreach ($patient in $patientsA) {
        $patientId = Get-PatientKey -Patient $patient -NsMgr $nsMgr
        if (-not $mapA.ContainsKey($patientId)) {
            $mapA[$patientId] = @()
        }
        $mapA[$patientId] += $patient
    }
    
    foreach ($patient in $patientsB) {
        $patientId = Get-PatientKey -Patient $patient -NsMgr $nsMgr
        if (-not $mapB.ContainsKey($patientId)) {
            $mapB[$patientId] = @()
        }
        $mapB[$patientId] += $patient
    }
    
    # Get all unique patient IDs
    $allPatientIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($id in $mapA.Keys) { [void]$allPatientIds.Add($id) }
    foreach ($id in $mapB.Keys) { [void]$allPatientIds.Add($id) }
    
    # Compare patients
    $comparisons = @()
    foreach ($patientId in $allPatientIds) {
        $inA = $mapA.ContainsKey($patientId)
        $inB = $mapB.ContainsKey($patientId)
        
        if ($inA -and $inB) {
            # Patient exists in both - compare them
            $patientA = $mapA[$patientId][0]
            $patientB = $mapB[$patientId][0]
            
            $isSame = Compare-PatientRecords -PatientA $patientA -PatientB $patientB -NsMgr $nsMgr
            
            $comparisons += @{
                PatientId = $patientId
                Status = if ($isSame) { "Same" } else { "Different" }
                InFileA = $true
                InFileB = $true
                PatientA = $patientA
                PatientB = $patientB
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
        elseif ($inA) {
            # Only in A
            $patientA = $mapA[$patientId][0]
            $comparisons += @{
                PatientId = $patientId
                Status = "OnlyInA"
                InFileA = $true
                InFileB = $false
                PatientA = $patientA
                PatientB = $null
                NameA = Get-PatientName -Patient $patientA -NsMgr $nsMgr
                NameB = ""
                TumorCountA = $patientA.SelectNodes("./n:Tumor", $nsMgr).Count
                TumorCountB = 0
            }
        }
        else {
            # Only in B
            $patientB = $mapB[$patientId][0]
            $comparisons += @{
                PatientId = $patientId
                Status = "OnlyInB"
                InFileA = $false
                InFileB = $true
                PatientA = $null
                PatientB = $patientB
                NameA = ""
                NameB = Get-PatientName -Patient $patientB -NsMgr $nsMgr
                TumorCountA = 0
                TumorCountB = $patientB.SelectNodes("./n:Tumor", $nsMgr).Count
            }
        }
    }
    
    # Calculate statistics
    $stats = @{
        TotalPatientsA = $patientsA.Count
        TotalPatientsB = $patientsB.Count
        Same = ($comparisons | Where-Object { $_.Status -eq "Same" }).Count
        Different = ($comparisons | Where-Object { $_.Status -eq "Different" }).Count
        OnlyInA = ($comparisons | Where-Object { $_.Status -eq "OnlyInA" }).Count
        OnlyInB = ($comparisons | Where-Object { $_.Status -eq "OnlyInB" }).Count
    }
    
    return @{
        Comparisons = $comparisons
        Stats = $stats
        NsMgr = $nsMgr
    }
}

function Get-PatientKey {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )
    
    $patientIdNode = $Patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", $NsMgr)
    if ($null -ne $patientIdNode) {
        return $patientIdNode.InnerText
    }
    
    # Fallback: use name + DOB
    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
    $dob = $Patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $NsMgr)
    
    $key = ""
    if ($lastName) { $key += $lastName.InnerText }
    if ($firstName) { $key += "|" + $firstName.InnerText }
    if ($dob) { $key += "|" + $dob.InnerText }
    
    if ([string]::IsNullOrWhiteSpace($key)) {
        return [guid]::NewGuid().ToString()
    }
    
    return $key
}

function Get-PatientName {
    param(
        [System.Xml.XmlElement]$Patient,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )
    
    $lastName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
    $firstName = $Patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
    
    $name = ""
    if ($lastName) { $name = $lastName.InnerText }
    if ($firstName) { 
        if ($name) { $name += ", " }
        $name += $firstName.InnerText 
    }
    
    return $name
}

function Compare-PatientRecords {
    param(
        [System.Xml.XmlElement]$PatientA,
        [System.Xml.XmlElement]$PatientB,
        [System.Xml.XmlNamespaceManager]$NsMgr
    )
    
    # Get XML strings for both patients
    $xmlA = $PatientA.OuterXml
    $xmlB = $PatientB.OuterXml
    
    # Normalize whitespace and compare
    $xmlA = $xmlA -replace '\s+', ' '
    $xmlB = $xmlB -replace '\s+', ' '
    
    return $xmlA -eq $xmlB
}

function Get-FormattedXmlLines {
    param(
        [string]$FilePath
    )
    
    try {
        # Load and format XML
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.PreserveWhitespace = $false
        $xmlDoc.Load($FilePath)
        
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.IndentChars = "  "
        $settings.NewLineChars = "`n"
        $settings.NewLineHandling = "Replace"
        $settings.OmitXmlDeclaration = $false
        
        $sw = New-Object System.IO.StringWriter
        $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
        $xmlDoc.Save($xw)
        $xw.Flush()
        $xw.Close()
        
        $formattedXml = $sw.ToString()
        $sw.Close()
        
        # Split into lines and ensure we return an array
        $lines = @($formattedXml -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
        
        return ,$lines
    }
    catch {
        throw "Error formatting XML: $($_.Exception.Message)"
    }
}

function Get-DiffLines {
    param(
        [string[]]$LinesA,
        [string[]]$LinesB
    )
    
    # Ensure we're working with arrays
    if ($null -eq $LinesA) { $LinesA = @() }
    if ($null -eq $LinesB) { $LinesB = @() }
    
    # Force to integer type to avoid array issues
    [int]$lenA = @($LinesA).Count
    [int]$lenB = @($LinesB).Count
    
    # Build LCS matrix using dynamic programming
    $lcs = New-Object 'int[,]' ($lenA + 1), ($lenB + 1)
    
    for ([int]$i = 1; $i -le $lenA; $i++) {
        for ([int]$j = 1; $j -le $lenB; $j++) {
            [int]$iMinus1 = $i - 1
            [int]$jMinus1 = $j - 1
            
            if ($LinesA[$iMinus1] -eq $LinesB[$jMinus1]) {
                $lcs[$i, $j] = $lcs[$iMinus1, $jMinus1] + 1
            }
            else {
                $val1 = $lcs[$iMinus1, $j]
                $val2 = $lcs[$i, $jMinus1]
                $lcs[$i, $j] = [Math]::Max($val1, $val2)
            }
        }
    }
    
    # Backtrack to build diff
    $diffLines = New-Object System.Collections.ArrayList
    [int]$i = $lenA
    [int]$j = $lenB
    
    while ($i -gt 0 -or $j -gt 0) {
        [int]$iMinus1 = $i - 1
        [int]$jMinus1 = $j - 1
        
        if ($i -gt 0 -and $j -gt 0 -and $LinesA[$iMinus1] -eq $LinesB[$jMinus1]) {
            # Unchanged line
            [void]$diffLines.Insert(0, @{
                LineNumA = $i
                LineNumB = $j
                Status = 'Unchanged'
                ContentA = $LinesA[$iMinus1]
                ContentB = $LinesB[$jMinus1]
            })
            $i--
            $j--
        }
        elseif ($j -gt 0 -and ($i -eq 0 -or $lcs[$i, $jMinus1] -ge $lcs[$iMinus1, $j])) {
            # Added line (only in B)
            [void]$diffLines.Insert(0, @{
                LineNumA = $null
                LineNumB = $j
                Status = 'Added'
                ContentA = ''
                ContentB = $LinesB[$jMinus1]
            })
            $j--
        }
        elseif ($i -gt 0) {
            # Deleted line (only in A)
            [void]$diffLines.Insert(0, @{
                LineNumA = $i
                LineNumB = $null
                Status = 'Deleted'
                ContentA = $LinesA[$iMinus1]
                ContentB = ''
            })
            $i--
        }
    }
    
    return $diffLines
}

function Show-DiffPreview {
    param(
        [hashtable]$DiffResult,
        [string]$FilePathA,
        [string]$FilePathB
    )
    
    $fileNameA = [System.IO.Path]::GetFileName($FilePathA)
    $fileNameB = [System.IO.Path]::GetFileName($FilePathB)
    
    # Create form
    $diffForm = New-Object System.Windows.Forms.Form
    $diffForm.Text = "File Diff: $fileNameA vs $fileNameB"
    $diffForm.Width = 1600
    $diffForm.Height = 900
    $diffForm.StartPosition = "CenterScreen"
    
    # Summary label
    $stats = $DiffResult.Stats
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 60)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    $summaryText = "File A: $fileNameA ($($stats.TotalPatientsA) patients)`n"
    $summaryText += "File B: $fileNameB ($($stats.TotalPatientsB) patients)`n"
    $summaryText += "Results: $($stats.Same) same, $($stats.Different) different, $($stats.OnlyInA) only in A, $($stats.OnlyInB) only in B"
    $lblSummary.Text = $summaryText
    
    # DataGridView for patient comparison
    $gridDiff = New-Object System.Windows.Forms.DataGridView
    $gridDiff.Location = New-Object System.Drawing.Point(10, 80)
    $gridDiff.Size = New-Object System.Drawing.Size(1560, 750)
    $gridDiff.Anchor = 'Top,Left,Right,Bottom'
    $gridDiff.ReadOnly = $true
    $gridDiff.AllowUserToAddRows = $false
    $gridDiff.AllowUserToDeleteRows = $false
    $gridDiff.RowHeadersVisible = $false
    $gridDiff.SelectionMode = 'FullRowSelect'
    $gridDiff.MultiSelect = $false
    $gridDiff.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    
    # Build DataTable
    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add("Status", [string])
    [void]$table.Columns.Add("PatientID", [string])
    [void]$table.Columns.Add("NameA", [string])
    [void]$table.Columns.Add("NameB", [string])
    [void]$table.Columns.Add("TumorsA", [int])
    [void]$table.Columns.Add("TumorsB", [int])
    
    foreach ($comp in $DiffResult.Comparisons) {
        $row = $table.NewRow()
        
        $row["Status"] = switch ($comp.Status) {
            "Same" { "Same" }
            "Different" { "Different" }
            "OnlyInA" { "Only in A" }
            "OnlyInB" { "Only in B" }
        }
        
        $row["PatientID"] = $comp.PatientId
        $row["NameA"] = $comp.NameA
        $row["NameB"] = $comp.NameB
        $row["TumorsA"] = $comp.TumorCountA
        $row["TumorsB"] = $comp.TumorCountB
        
        [void]$table.Rows.Add($row)
    }
    
    $gridDiff.DataSource = $table
    
    # Configure columns after DataSource is set
    if ($gridDiff.Columns.Count -ge 6) {
        $col0 = $gridDiff.Columns[0]
        $col1 = $gridDiff.Columns[1]
        $col2 = $gridDiff.Columns[2]
        $col3 = $gridDiff.Columns[3]
        $col4 = $gridDiff.Columns[4]
        $col5 = $gridDiff.Columns[5]
        
        if ($null -ne $col0) { $col0.Width = 100 }      # Status
        if ($null -ne $col1) { $col1.Width = 150 }      # PatientID
        if ($null -ne $col2) { $col2.AutoSizeMode = 'Fill' }  # NameA
        if ($null -ne $col3) { $col3.AutoSizeMode = 'Fill' }  # NameB
        if ($null -ne $col4) { $col4.Width = 80 }       # TumorsA
        if ($null -ne $col5) { $col5.Width = 80 }       # TumorsB
    }
    
    # Color coding based on status
    $gridDiff.add_RowPrePaint({
        param($sender, $e)
        $row = $sender.Rows[$e.RowIndex]
        $status = [string]$row.Cells[0].Value
        
        switch ($status) {
            "Same" { 
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White 
            }
            "Different" { 
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow 
            }
            "Only in A" { 
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightBlue 
            }
            "Only in B" { 
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen 
            }
        }
    })
    
    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(1470, 840)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({
        $diffForm.Close()
    })
    
    # Add controls to form
    $diffForm.Controls.AddRange(@($lblSummary, $gridDiff, $btnClose))
    
    # Show form
    [void]$diffForm.ShowDialog()
}
