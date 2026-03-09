function Get-BtnOpenHandler {
    param(
        [hashtable]$Controls
    )

    return {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "NAACCR/HL7 Files (*.xml;*.hl7)|*.xml;*.hl7|NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*"
        $ofd.Title  = "Select NAACCR XML or HL7 file"

        $lastDir = Get-LastOpenedDirectory
        if ($null -ne $lastDir) {
            $ofd.InitialDirectory = $lastDir
        }

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $extension = [System.IO.Path]::GetExtension($ofd.FileName).ToLower()

            if ($extension -eq ".hl7") {
                Import-Hl7File -FilePath $ofd.FileName -Controls $Controls
            }
            else {
                Import-XmlFile -FilePath $ofd.FileName -Controls $Controls
            }
        }
    }
}

function Import-XmlFile {
    param(
        [string]$FilePath,
        [hashtable]$Controls
    )

    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($FilePath)

        $script:XmlDoc = $xml
        $script:CurrentFilePath = $FilePath
        $script:FileType = 'xml'

        # Clear HL7 data
        $script:Hl7Messages = @()

        Update-ButtonStatesForFileType -Controls $Controls -FileType 'xml'

        $nsUri = $xml.DocumentElement.NamespaceURI
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("n", $nsUri)

        $script:NsMgr = $nsMgr
        $tumors = $xml.SelectNodes("//n:Tumor", $nsMgr)
        $script:Tumors = $tumors
        $script:CurrentIndex = -1

        if ($script:Tumors.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No <Tumor> elements found in this file.", "No Tumors")
            $fileName = [System.IO.Path]::GetFileName($FilePath)
            $Controls['lblStatus'].Text = "No tumors found"
            $Controls['lblFileName'].Text = "File: $FilePath"
            $Controls['rtbPath'].Clear()
            $Controls['rtbItems'].Clear()
            $Controls['gridNav'].DataSource = $null
            $Controls['btnPrev'].Enabled = $false
            $Controls['btnNext'].Enabled = $false
            $Controls['lblIndex'].Text = ""
            $Controls['pnlSearch'].Visible = $false
        }
        else {
            $fileName = [System.IO.Path]::GetFileName($FilePath)
            $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f $fileName, $script:Tumors.Count
            $Controls['lblFileName'].Text = "File: $FilePath"

            Write-ParatLog -Level INFO -Message "Loaded $fileName with $($script:Tumors.Count) tumors" -Action "OPEN_FILE"

            Add-RecentFile -FilePath $FilePath -FileType 'xml'

            # Build navigation table
            $table = New-Object System.Data.DataTable
            [void]$table.Columns.Add("Selected", [bool])
            [void]$table.Columns.Add("Index", [int])
            [void]$table.Columns.Add("nameLast", [string])
            [void]$table.Columns.Add("nameFirst", [string])
            [void]$table.Columns.Add("dateOfBirth", [string])
            [void]$table.Columns.Add("pathReportNumber1", [string])
            [void]$table.Columns.Add("primarySite", [string])
            [void]$table.Columns.Add("dateOfDiagnosis", [string])

            # Helper function to build a hashtable of Item values by naaccrId
            $buildItemLookup = {
                param($parentNode)
                $lookup = @{}
                if ($null -ne $parentNode) {
                    foreach ($child in $parentNode.ChildNodes) {
                        if ($child -is [System.Xml.XmlElement] -and $child.LocalName -eq "Item") {
                            $naaccrId = $child.GetAttribute("naaccrId")
                            if (-not [string]::IsNullOrEmpty($naaccrId)) {
                                $lookup[$naaccrId] = $child.InnerText
                            }
                        }
                    }
                }
                return $lookup
            }

            $table.BeginLoadData()
            for ($i = 0; $i -lt $script:Tumors.Count; $i++) {
                $tumor = $script:Tumors[$i]
                $patient = $tumor.ParentNode
                # Navigate up to Patient if not direct parent
                while ($null -ne $patient -and $patient.LocalName -ne "Patient") {
                    $patient = $patient.ParentNode
                }

                # Build lookups once per tumor/patient for O(1) access
                $patientItems = & $buildItemLookup $patient
                $tumorItems = & $buildItemLookup $tumor

                $row = $table.NewRow()
                $row["Selected"] = $false
                $row["Index"] = $i + 1
                $row["nameLast"] = if ($patientItems.ContainsKey("nameLast")) { $patientItems["nameLast"] } else { "" }
                $row["nameFirst"] = if ($patientItems.ContainsKey("nameFirst")) { $patientItems["nameFirst"] } else { "" }
                $row["dateOfBirth"] = if ($patientItems.ContainsKey("dateOfBirth")) { $patientItems["dateOfBirth"] } else { "" }
                $row["pathReportNumber1"] = if ($tumorItems.ContainsKey("pathReportNumber1")) { $tumorItems["pathReportNumber1"] } else { "" }
                $row["primarySite"] = if ($tumorItems.ContainsKey("primarySite")) { $tumorItems["primarySite"] } else { "" }
                $row["dateOfDiagnosis"] = if ($tumorItems.ContainsKey("dateOfDiagnosis")) { $tumorItems["dateOfDiagnosis"] } else { "" }

                [void]$table.Rows.Add($row)
            }
            $table.EndLoadData()

            $script:NavTable = $table

            # Temporarily disable event handling while loading data
            $script:IsLoadingData = $true
            $Controls['gridNav'].DataSource = $table

            # Configure columns after data binding
            $Controls['gridNav'].Columns["Selected"].ReadOnly = $false
            $Controls['gridNav'].Columns["Index"].ReadOnly = $true
            $Controls['gridNav'].Columns["nameLast"].ReadOnly = $true
            $Controls['gridNav'].Columns["nameFirst"].ReadOnly = $true
            $Controls['gridNav'].Columns["dateOfBirth"].ReadOnly = $true
            $Controls['gridNav'].Columns["pathReportNumber1"].ReadOnly = $true
            $Controls['gridNav'].Columns["dateOfDiagnosis"].ReadOnly = $true
            $Controls['gridNav'].Columns["primarySite"].ReadOnly = $true

            # Set checkbox column width and move to first position
            $Controls['gridNav'].Columns["Selected"].Width = 60
            $Controls['gridNav'].Columns["Selected"].DisplayIndex = 0

            # Ensure checkbox column is properly configured as checkbox
            $checkboxColumn = $Controls['gridNav'].Columns["Selected"]
            if ($checkboxColumn -is [System.Windows.Forms.DataGridViewCheckBoxColumn]) {
                # Already a checkbox column, good
            } else {
                # Convert to checkbox column if needed
                $checkboxColumn.CellTemplate = New-Object System.Windows.Forms.DataGridViewCheckBoxCell
            }

            # Allow sorting by clicking column headers (except checkbox)
            foreach ($col in $Controls['gridNav'].Columns) {
                if ($col.Name -ne "Selected") {
                    $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
                } else {
                    $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
                }
            }

            # Re-enable event handling
            $script:IsLoadingData = $false

            Show-Tumor -Index 0

            $script:SearchIndex = New-SearchIndex -FileType 'xml'
            $Controls['pnlSearch'].Visible = $true
            $Controls['txtSearch'].Text = ""
            $Controls['lblSearchCount'].Text = ""
        }
    }
    catch {
        Write-ParatError -Message "Failed to load XML file" -Action "OPEN_FILE" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show("Error loading XML: {0}" -f $_.Exception.Message, "Error")
    }
}

function Import-Hl7File {
    param(
        [string]$FilePath,
        [hashtable]$Controls
    )

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding ASCII

        if ([string]::IsNullOrWhiteSpace($content)) {
            [System.Windows.Forms.MessageBox]::Show("File is empty.", "No Data")
            return
        }

        $messages = ConvertFrom-Hl7Content -Content $content

        if ($messages.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No HL7 messages found in this file.", "No Messages")
            $fileName = [System.IO.Path]::GetFileName($FilePath)
            $Controls['lblStatus'].Text = "No messages found"
            $Controls['lblFileName'].Text = "File: $FilePath"
            $Controls['rtbPath'].Clear()
            $Controls['rtbItems'].Clear()
            $Controls['gridNav'].DataSource = $null
            $Controls['btnPrev'].Enabled = $false
            $Controls['btnNext'].Enabled = $false
            $Controls['lblIndex'].Text = ""
            $Controls['pnlSearch'].Visible = $false
            return
        }

        # Set state
        $script:Hl7Messages = $messages
        $script:CurrentFilePath = $FilePath
        $script:FileType = 'hl7'
        $script:CurrentIndex = -1

        # Clear XML data
        $script:XmlDoc = $null
        $script:Tumors = @()
        $script:NsMgr = $null

        Update-ButtonStatesForFileType -Controls $Controls -FileType 'hl7'

        $fileName = [System.IO.Path]::GetFileName($FilePath)
        $Controls['lblStatus'].Text = "Loaded: {0} (Messages: {1})" -f $fileName, $messages.Count
        $Controls['lblFileName'].Text = "File: $FilePath"

        Write-ParatLog -Level INFO -Message "Loaded $fileName with $($messages.Count) messages" -Action "OPEN_FILE"

        Add-RecentFile -FilePath $FilePath -FileType 'hl7'

        # Build navigation table for HL7
        $table = New-Object System.Data.DataTable
        [void]$table.Columns.Add("Selected", [bool])
        [void]$table.Columns.Add("Index", [int])
        [void]$table.Columns.Add("nameLast", [string])
        [void]$table.Columns.Add("nameFirst", [string])
        [void]$table.Columns.Add("dateOfBirth", [string])
        [void]$table.Columns.Add("patientId", [string])
        [void]$table.Columns.Add("messageType", [string])
        [void]$table.Columns.Add("orderDateTime", [string])

        $table.BeginLoadData()
        foreach ($msg in $messages) {
            $row = $table.NewRow()
            $row["Selected"] = $false
            $row["Index"] = $msg.Index + 1
            $row["nameLast"] = $msg.PatientLastName
            $row["nameFirst"] = $msg.PatientFirstName
            $row["dateOfBirth"] = $msg.DateOfBirth
            $row["patientId"] = $msg.PatientId
            $row["messageType"] = $msg.MessageType
            $row["orderDateTime"] = $msg.OrderDateTime

            [void]$table.Rows.Add($row)
        }
        $table.EndLoadData()

        $script:NavTable = $table

        # Temporarily disable event handling while loading data
        $script:IsLoadingData = $true
        $Controls['gridNav'].DataSource = $table

        # Configure columns after data binding
        $Controls['gridNav'].Columns["Selected"].ReadOnly = $false
        $Controls['gridNav'].Columns["Index"].ReadOnly = $true
        $Controls['gridNav'].Columns["nameLast"].ReadOnly = $true
        $Controls['gridNav'].Columns["nameFirst"].ReadOnly = $true
        $Controls['gridNav'].Columns["dateOfBirth"].ReadOnly = $true
        $Controls['gridNav'].Columns["patientId"].ReadOnly = $true
        $Controls['gridNav'].Columns["messageType"].ReadOnly = $true
        $Controls['gridNav'].Columns["orderDateTime"].ReadOnly = $true

        # Set checkbox column width and move to first position
        $Controls['gridNav'].Columns["Selected"].Width = 60
        $Controls['gridNav'].Columns["Selected"].DisplayIndex = 0

        # Ensure checkbox column is properly configured as checkbox
        $checkboxColumn = $Controls['gridNav'].Columns["Selected"]
        if ($checkboxColumn -is [System.Windows.Forms.DataGridViewCheckBoxColumn]) {
            # Already a checkbox column, good
        } else {
            # Convert to checkbox column if needed
            $checkboxColumn.CellTemplate = New-Object System.Windows.Forms.DataGridViewCheckBoxCell
        }

        # Allow sorting by clicking column headers (except checkbox)
        foreach ($col in $Controls['gridNav'].Columns) {
            if ($col.Name -ne "Selected") {
                $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
            } else {
                $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
            }
        }

        # Re-enable event handling
        $script:IsLoadingData = $false

        # Select first row and show first message
        if ($Controls['gridNav'].Rows.Count -gt 0) {
            $Controls['gridNav'].Rows[0].Selected = $true
            $Controls['gridNav'].CurrentCell = $Controls['gridNav'].Rows[0].Cells[0]
        }
        Show-Hl7Message -Index 0 -Messages $messages -Controls $Controls

        $script:SearchIndex = New-SearchIndex -FileType 'hl7'
        $Controls['pnlSearch'].Visible = $true
        $Controls['txtSearch'].Text = ""
        $Controls['lblSearchCount'].Text = ""
    }
    catch {
        Write-ParatError -Message "Failed to load HL7 file" -Action "OPEN_FILE" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show("Error loading HL7: {0}" -f $_.Exception.Message, "Error")
    }
}


