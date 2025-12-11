function Get-BtnOpenHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )
    
    return {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*"
        $ofd.Title  = "Select NAACCR XML file"

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $xml = New-Object System.Xml.XmlDocument
                $xml.XmlResolver = $null
                $xml.Load($ofd.FileName)

                $ScriptVars['XmlDoc'] = $xml
                $ScriptVars['CurrentFilePath'] = $ofd.FileName

                $nsUri = $xml.DocumentElement.NamespaceURI
                $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
                $nsMgr.AddNamespace("n", $nsUri)

                $ScriptVars['NsMgr'] = $nsMgr
                $ScriptVars['Tumors'] = $xml.SelectNodes("//n:Tumor", $nsMgr)
                $ScriptVars['CurrentIndex'] = -1

                if ($ScriptVars['Tumors'].Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show("No <Tumor> elements found in this file.", "No Tumors")
                    $Controls['lblStatus'].Text = "No tumors found"
                    $Controls['rtbPath'].Clear()
                    $Controls['rtbItems'].Clear()
                    $Controls['gridNav'].DataSource = $null
                    $Controls['btnPrev'].Enabled = $false
                    $Controls['btnNext'].Enabled = $false
                    $Controls['lblIndex'].Text = ""
                }
                else {
                    $fileName = [System.IO.Path]::GetFileName($ofd.FileName)
                    $Controls['lblStatus'].Text = "Loaded: {0} (Tumors: {1})" -f $fileName, $ScriptVars['Tumors'].Count

                    # Build navigation table
                    $table = New-Object System.Data.DataTable
                    [void]$table.Columns.Add("Selected", [bool])
                    [void]$table.Columns.Add("Index", [int])
                    [void]$table.Columns.Add("nameLast", [string])
                    [void]$table.Columns.Add("nameFirst", [string])
                    [void]$table.Columns.Add("dateOfDiagnosis", [string])
                    [void]$table.Columns.Add("pathReportNumber1", [string])

                    for ($i = 0; $i -lt $ScriptVars['Tumors'].Count; $i++) {
                        $tumor = $ScriptVars['Tumors'][$i]
                        $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $ScriptVars['NsMgr'])

                        $nameLast = ""
                        $nameFirst = ""
                        $dxDate = ""
                        $pathReportNumber1 = ""

                        if ($patient -ne $null) {
                            $nlNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $ScriptVars['NsMgr'])
                            $nfNode = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $ScriptVars['NsMgr'])

                            if ($nlNode) { $nameLast = $nlNode.InnerText }
                            if ($nfNode) { $nameFirst = $nfNode.InnerText }
                        }

                        $dxNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", $ScriptVars['NsMgr'])
                        if ($dxNode) { $dxDate = $dxNode.InnerText }
                        
                        $pathNode = $tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", $ScriptVars['NsMgr'])
                        if ($pathNode) { $pathReportNumber1 = $pathNode.InnerText }

                        $row = $table.NewRow()
                        $row["Selected"] = $false
                        $row["Index"] = $i + 1
                        $row["nameLast"] = $nameLast
                        $row["nameFirst"] = $nameFirst
                        $row["pathReportNumber1"] = $pathReportNumber1
                        $row["dateOfDiagnosis"] = $dxDate

                        [void]$table.Rows.Add($row)
                    }

                    $ScriptVars['NavTable'] = $table
                    $Controls['gridNav'].DataSource = $table

                    # Configure columns after data binding
                    $Controls['gridNav'].Columns["Selected"].ReadOnly = $false
                    $Controls['gridNav'].Columns["Index"].ReadOnly = $true
                    $Controls['gridNav'].Columns["nameLast"].ReadOnly = $true
                    $Controls['gridNav'].Columns["nameFirst"].ReadOnly = $true
                    $Controls['gridNav'].Columns["dateOfDiagnosis"].ReadOnly = $true
                    $Controls['gridNav'].Columns["pathReportNumber1"].ReadOnly = $true
                    
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

                    Show-Tumor -Index 0
                }
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Error loading XML: {0}" -f $_.Exception.Message, "Error")
            }
        }
    }
}
