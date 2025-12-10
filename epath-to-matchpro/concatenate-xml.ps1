# concatenate-xml.ps1
# NAACCR XML concatenation utilities

. "$PSScriptRoot\xml-helpers.ps1"

function Get-XmlHeaderInfo {
    param(
        [string]$FilePath
    )
    
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($FilePath)
        
        # Get XML declaration version
        $declNode = $xml.ChildNodes | Where-Object { $_ -is [System.Xml.XmlDeclaration] } | Select-Object -First 1
        $xmlVersion = if ($declNode) { $declNode.Version } else { "1.0" }
        
        # Get NaaccrData attributes
        $root = $xml.DocumentElement
        if ($root -eq $null -or $root.LocalName -ne "NaaccrData") {
            throw "Root element is not NaaccrData"
        }
        
        $baseDictionaryUri = $root.GetAttribute("baseDictionaryUri")
        $xmlns = $root.NamespaceURI
        $recordType = $root.GetAttribute("recordType")
        
        # Get tumor count
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("n", $xmlns)
        $tumors = $xml.SelectNodes("//n:Tumor", $nsMgr)
        $tumorCount = $tumors.Count
        
        return @{
            XmlVersion = $xmlVersion
            BaseDictionaryUri = $baseDictionaryUri
            Xmlns = $xmlns
            RecordType = $recordType
            TumorCount = $tumorCount
            XmlDoc = $xml
            NsMgr = $nsMgr
            Tumors = $tumors
            Success = $true
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Validate-XmlHeaders {
    param(
        [array]$XmlFiles
    )
    
    if ($XmlFiles.Count -eq 0) {
        return @{ Success = $false; Error = "No files provided" }
    }
    
    $headerInfos = @()
    $errors = @()
    
    # Load and validate each file
    foreach ($file in $XmlFiles) {
        $info = Get-XmlHeaderInfo -FilePath $file
        if (-not $info.Success) {
            $errors += "Error loading $file : $($info.Error)"
            continue
        }
        
        $headerInfos += @{
            FilePath = $file
            Info = $info
        }
    }
    
    if ($errors.Count -gt 0) {
        return @{
            Success = $false
            Error = ($errors -join "`n")
        }
    }
    
    if ($headerInfos.Count -eq 0) {
        return @{ Success = $false; Error = "No valid XML files found" }
    }
    
    # Check if all headers match
    $first = $headerInfos[0].Info
    
    foreach ($item in $headerInfos) {
        $info = $item.Info
        
        if ($info.XmlVersion -ne $first.XmlVersion) {
            return @{
                Success = $false
                Error = "XML version mismatch. File '$($item.FilePath)' has version '$($info.XmlVersion)' but expected '$($first.XmlVersion)'"
            }
        }
        
        if ($info.BaseDictionaryUri -ne $first.BaseDictionaryUri) {
            return @{
                Success = $false
                Error = "baseDictionaryUri mismatch. File '$($item.FilePath)' has '$($info.BaseDictionaryUri)' but expected '$($first.BaseDictionaryUri)'"
            }
        }
        
        if ($info.Xmlns -ne $first.Xmlns) {
            return @{
                Success = $false
                Error = "xmlns mismatch. File '$($item.FilePath)' has '$($info.Xmlns)' but expected '$($first.Xmlns)'"
            }
        }
        
        if ($info.RecordType -ne $first.RecordType) {
            return @{
                Success = $false
                Error = "recordType mismatch. File '$($item.FilePath)' has '$($info.RecordType)' but expected '$($first.RecordType)'"
            }
        }
    }
    
    return @{
        Success = $true
        HeaderInfos = $headerInfos
        ReferenceInfo = $first
    }
}

function Get-TumorPreview {
    param(
        [System.Xml.XmlNodeList]$Tumors,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [int]$MaxTumors = 100
    )
    
    $preview = @()
    $count = [Math]::Min($Tumors.Count, $MaxTumors)
    
    for ($i = 0; $i -lt $count; $i++) {
        $tumor = $Tumors[$i]
        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)
        
        $nameLast = ""
        $nameFirst = ""
        $dateOfDiagnosis = ""
        $pathReportNumber1 = ""
        
        if ($patient -ne $null) {
            $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $NsMgr)
            $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $NsMgr)
            
            if ($nlNode) { $nameLast = $nlNode.InnerText }
            if ($nfNode) { $nameFirst = $nfNode.InnerText }
        }
        
        $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $NsMgr)
        if ($dxNode) { $dateOfDiagnosis = $dxNode.InnerText }
        
        $pathNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $NsMgr)
        if ($pathNode) { $pathReportNumber1 = $pathNode.InnerText }
        
        $preview += [PSCustomObject]@{
            TumorIndex = $i + 1
            NameLast = $nameLast
            NameFirst = $nameFirst
            DateOfDiagnosis = $dateOfDiagnosis
            PathReportNumber1 = $pathReportNumber1
        }
    }
    
    return $preview
}

function Show-ConcatenationPreview {
    param(
        [array]$XmlFiles
    )
    
    # Validate headers
    $validation = Validate-XmlHeaders -XmlFiles $XmlFiles
    if (-not $validation.Success) {
        [System.Windows.Forms.MessageBox]::Show(
            "Cannot concatenate XMLs:`n`n$($validation.Error)",
            "Validation Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    $headerInfos = $validation.HeaderInfos
    $refInfo = $validation.ReferenceInfo
    
    # Calculate totals
    $totalTumors = ($headerInfos | ForEach-Object { $_.Info.TumorCount } | Measure-Object -Sum).Sum
    
    # Create preview form
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = "Concatenate XML Files - Preview"
    $previewForm.Width = 1600
    $previewForm.Height = 800
    $previewForm.StartPosition = "CenterScreen"
    
    # Summary label
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(10, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1560, 40)
    $lblSummary.Text = "Files: $($headerInfos.Count) | Total Tumors: $totalTumors | XML Version: $($refInfo.XmlVersion) | Record Type: $($refInfo.RecordType)"
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    # Split container for file list and tumor preview
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Location = New-Object System.Drawing.Point(10, 60)
    $splitContainer.Size = New-Object System.Drawing.Size(1560, 630)
    $splitContainer.Anchor = 'Top,Left,Right,Bottom'
    $splitContainer.Orientation = 'Vertical'
    $splitContainer.SplitterDistance = 300
    
    # DataGridView for file list (left)
    $gridFiles = New-Object System.Windows.Forms.DataGridView
    $gridFiles.Dock = 'Fill'
    $gridFiles.ReadOnly = $true
    $gridFiles.AllowUserToAddRows = $false
    $gridFiles.AllowUserToDeleteRows = $false
    $gridFiles.RowHeadersVisible = $false
    $gridFiles.AutoSizeColumnsMode = "Fill"
    $gridFiles.SelectionMode = 'FullRowSelect'
    $gridFiles.MultiSelect = $false
    
    # Build file list DataTable
    $tableFiles = New-Object System.Data.DataTable
    [void]$tableFiles.Columns.Add("FileName", [string])
    [void]$tableFiles.Columns.Add("TumorCount", [int])
    [void]$tableFiles.Columns.Add("FilePath", [string])
    
    foreach ($item in $headerInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $row = $tableFiles.NewRow()
        $row["FileName"] = $fileName
        $row["TumorCount"] = $item.Info.TumorCount
        $row["FilePath"] = $item.FilePath
        [void]$tableFiles.Rows.Add($row)
    }
    
    $gridFiles.DataSource = $tableFiles
    
    # DataGridView for tumor preview (right)
    $gridTumors = New-Object System.Windows.Forms.DataGridView
    $gridTumors.Dock = 'Fill'
    $gridTumors.ReadOnly = $true
    $gridTumors.AllowUserToAddRows = $false
    $gridTumors.AllowUserToDeleteRows = $false
    $gridTumors.RowHeadersVisible = $false
    $gridTumors.AutoSizeColumnsMode = "Fill"
    $gridTumors.SelectionMode = 'FullRowSelect'
    $gridTumors.MultiSelect = $false
    
    # Build combined tumor preview DataTable
    $tableTumors = New-Object System.Data.DataTable
    [void]$tableTumors.Columns.Add("File", [string])
    [void]$tableTumors.Columns.Add("TumorIndex", [int])
    [void]$tableTumors.Columns.Add("NameLast", [string])
    [void]$tableTumors.Columns.Add("NameFirst", [string])
    [void]$tableTumors.Columns.Add("DateOfDiagnosis", [string])
    [void]$tableTumors.Columns.Add("PathReportNumber1", [string])
    
    # Combine all tumor previews
    foreach ($item in $headerInfos) {
        $fileName = [System.IO.Path]::GetFileName($item.FilePath)
        $preview = Get-TumorPreview -Tumors $item.Info.Tumors -NsMgr $item.Info.NsMgr
        
        foreach ($tumor in $preview) {
            $row = $tableTumors.NewRow()
            $row["File"] = $fileName
            $row["TumorIndex"] = $tumor.TumorIndex
            $row["NameLast"] = $tumor.NameLast
            $row["NameFirst"] = $tumor.NameFirst
            $row["DateOfDiagnosis"] = $tumor.DateOfDiagnosis
            $row["PathReportNumber1"] = $tumor.PathReportNumber1
            [void]$tableTumors.Rows.Add($row)
        }
    }
    
    $gridTumors.DataSource = $tableTumors
    
    # Add to split container
    $splitContainer.Panel1.Controls.Add($gridFiles)
    $splitContainer.Panel2.Controls.Add($gridTumors)
    
    # Buttons
    $btnConcatenate = New-Object System.Windows.Forms.Button
    $btnConcatenate.Text = "Concatenate and Save"
    $btnConcatenate.Width = 180
    $btnConcatenate.Location = New-Object System.Drawing.Point(10, 710)
    $btnConcatenate.Anchor = 'Bottom,Left'
    
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Width = 100
    $btnClose.Location = New-Object System.Drawing.Point(200, 710)
    $btnClose.Anchor = 'Bottom,Left'
    
    # Concatenate button handler
    $btnConcatenate.Add_Click({
        # Get output directory
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select output directory for concatenated XML"
        
        if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $outputDir = $folderDialog.SelectedPath
        
        # Get output filename
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "Enter Output Filename"
        $inputForm.Width = 400
        $inputForm.Height = 150
        $inputForm.StartPosition = "CenterScreen"
        
        $lblPrompt = New-Object System.Windows.Forms.Label
        $lblPrompt.Location = New-Object System.Drawing.Point(10, 10)
        $lblPrompt.Size = New-Object System.Drawing.Size(370, 40)
        $lblPrompt.Text = "Enter the output filename (without .xml extension):"
        
        $txtFilename = New-Object System.Windows.Forms.TextBox
        $txtFilename.Location = New-Object System.Drawing.Point(10, 50)
        $txtFilename.Width = 370
        $txtFilename.Text = "concatenated"
        
        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.Location = New-Object System.Drawing.Point(200, 80)
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(280, 80)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        
        $inputForm.Controls.AddRange(@($lblPrompt, $txtFilename, $btnOk, $btnCancel))
        $inputForm.AcceptButton = $btnOk
        $inputForm.CancelButton = $btnCancel
        
        $result = $inputForm.ShowDialog()
        
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $filename = $txtFilename.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($filename)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Filename cannot be empty.",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }
        
        # Ensure .xml extension
        if (-not $filename.EndsWith(".xml", [System.StringComparison]::OrdinalIgnoreCase)) {
            $filename += ".xml"
        }
        
        $outputPath = [System.IO.Path]::Combine($outputDir, $filename)
        
        # Check if file exists
        if (Test-Path $outputPath) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                "File already exists:`n$outputPath`n`nOverwrite?",
                "File Exists",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }
        
        try {
            # Concatenate XMLs
            Write-ConcatenatedXml -HeaderInfos $headerInfos -ReferenceInfo $refInfo -OutputPath $outputPath
            
            [System.Windows.Forms.MessageBox]::Show(
                "Concatenated XML saved to:`n$outputPath`n`nTotal tumors: $totalTumors",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            $previewForm.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error concatenating XMLs: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })
    
    # Close button handler
    $btnClose.Add_Click({
        $previewForm.Close()
    })
    
    # Add controls to form
    $previewForm.Controls.AddRange(@($lblSummary, $splitContainer, $btnConcatenate, $btnClose))
    
    [void]$previewForm.ShowDialog()
}

function Write-ConcatenatedXml {
    param(
        [array]$HeaderInfos,
        [hashtable]$ReferenceInfo,
        [string]$OutputPath
    )
    
    # Create new XML document
    $newDoc = New-Object System.Xml.XmlDocument
    $newDoc.XmlResolver = $null
    
    # Add XML declaration
    $newDecl = $newDoc.CreateXmlDeclaration($ReferenceInfo.XmlVersion, "UTF-8", $null)
    [void]$newDoc.AppendChild($newDecl)
    
    # Create NaaccrData root element
    $newRoot = $newDoc.CreateElement("NaaccrData", $ReferenceInfo.Xmlns)
    $newRoot.SetAttribute("baseDictionaryUri", $ReferenceInfo.BaseDictionaryUri)
    $newRoot.SetAttribute("recordType", $ReferenceInfo.RecordType)
    $newRoot.SetAttribute("timeGenerated", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"))
    $newRoot.SetAttribute("specificationVersion", "1.7")
    [void]$newDoc.AppendChild($newRoot)
    
    # Concatenate all Patient elements from all files
    foreach ($item in $HeaderInfos) {
        $xmlDoc = $item.Info.XmlDoc
        $nsMgr = $item.Info.NsMgr
        $root = $xmlDoc.DocumentElement
        
        # Get all Patient nodes from this file
        $patients = $root.SelectNodes("./n:Patient", $nsMgr)
        
        foreach ($patient in $patients) {
            # Import the patient node (deep copy)
            $importedPatient = $newDoc.ImportNode($patient, $true)
            [void]$newRoot.AppendChild($importedPatient)
        }
    }
    
    # Save with formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = "Replace"
    
    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    $newDoc.Save($writer)
    $writer.Close()
}

function Start-ConcatenateXml {
    # Open file dialog for multiple file selection
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
    $ofd.Title = "Select XML files to concatenate (hold Ctrl or Shift to select multiple)"
    $ofd.Multiselect = $true
    
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($ofd.FileNames.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No files selected.",
                "No Files",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        Show-ConcatenationPreview -XmlFiles $ofd.FileNames
    }
}
