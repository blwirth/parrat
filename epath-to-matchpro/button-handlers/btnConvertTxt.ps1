function Get-BtnConvertTxtHandler {
    return {
        try {
            # Create and show the HL7 converter dialog
            $converterForm = New-Object System.Windows.Forms.Form
            $converterForm.Text = "Convert Pathology Text to HL7"
            $converterForm.Size = New-Object System.Drawing.Size(1200, 800)
            $converterForm.StartPosition = "CenterScreen"
            $converterForm.MinimumSize = New-Object System.Drawing.Size(1000, 600)

            # Top panel for file selection and configuration
            $topPanel = New-Object System.Windows.Forms.Panel
            $topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
            $topPanel.Height = 120
            $topPanel.Padding = New-Object System.Windows.Forms.Padding(10)

            # Input file selection
            $lblInput = New-Object System.Windows.Forms.Label
            $lblInput.Text = "Input File (Level_1):"
            $lblInput.Location = New-Object System.Drawing.Point(10, 15)
            $lblInput.AutoSize = $true
            $topPanel.Controls.Add($lblInput)

            $txtInput = New-Object System.Windows.Forms.TextBox
            $txtInput.Location = New-Object System.Drawing.Point(10, 35)
            $txtInput.Width = 900  # initial; will be overridden by layout handler
            $txtInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor `
                               [System.Windows.Forms.AnchorStyles]::Left -bor `
                               [System.Windows.Forms.AnchorStyles]::Right
            $topPanel.Controls.Add($txtInput)

            $btnBrowseInput = New-Object System.Windows.Forms.Button
            $btnBrowseInput.Text = "Browse..."
            $btnBrowseInput.Location = New-Object System.Drawing.Point(920, 33)  # initial; overridden
            $btnBrowseInput.Width = 80
            $btnBrowseInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor `
                                      [System.Windows.Forms.AnchorStyles]::Right
            $topPanel.Controls.Add($btnBrowseInput)

            # Facility selection
            $lblFacility = New-Object System.Windows.Forms.Label
            $lblFacility.Text = "Facility:"
            $lblFacility.Location = New-Object System.Drawing.Point(10, 70)
            $lblFacility.AutoSize = $true
            $topPanel.Controls.Add($lblFacility)

            $cmbFacility = New-Object System.Windows.Forms.ComboBox
            $cmbFacility.Location = New-Object System.Drawing.Point(80, 68)
            $cmbFacility.Width = 150
            $cmbFacility.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            [void]$cmbFacility.Items.Add("Parkland")
            [void]$cmbFacility.Items.Add("Portsmouth")
            [void]$cmbFacility.Items.Add("Frisbie")
            $cmbFacility.SelectedIndex = 0
            $topPanel.Controls.Add($cmbFacility)

            # Convert button (initially disabled)
            $btnConvert = New-Object System.Windows.Forms.Button
            $btnConvert.Text = "Convert to HL7"
            $btnConvert.Location = New-Object System.Drawing.Point(250, 66)
            $btnConvert.Width = 150
            $btnConvert.Height = 30
            $btnConvert.Enabled = $false
            $topPanel.Controls.Add($btnConvert)

            # Status label
            $lblConverterStatus = New-Object System.Windows.Forms.Label
            $lblConverterStatus.Location = New-Object System.Drawing.Point(410, 72)
            $lblConverterStatus.Width = 400
            $lblConverterStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor `
                                         [System.Windows.Forms.AnchorStyles]::Left -bor `
                                         [System.Windows.Forms.AnchorStyles]::Right
            $lblConverterStatus.Text = "Select input file to begin"
            $topPanel.Controls.Add($lblConverterStatus)

            # Split container for preview
            $splitContainer = New-Object System.Windows.Forms.SplitContainer
            $splitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
            $splitContainer.Orientation = [System.Windows.Forms.Orientation]::Vertical
            $splitContainer.SplitterDistance = 500

            # Left panel - Case list with label docked at top
            $lblCases = New-Object System.Windows.Forms.Label
            $lblCases.Text = "Parsed Cases:"
            $lblCases.Dock = [System.Windows.Forms.DockStyle]::Top
            $lblCases.Height = 20
            $lblCases.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)

            $dgvCases = New-Object System.Windows.Forms.DataGridView
            $dgvCases.Dock = [System.Windows.Forms.DockStyle]::Fill
            $dgvCases.AllowUserToAddRows = $false
            $dgvCases.AllowUserToDeleteRows = $false
            $dgvCases.ReadOnly = $true
            $dgvCases.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
            $dgvCases.MultiSelect = $false
            $dgvCases.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::AllCells

            $splitContainer.Panel1.Controls.Add($dgvCases)
            $splitContainer.Panel1.Controls.Add($lblCases)  # label on top

            # Right panel - Case details (split into three sections)
            $rightSplitContainer = New-Object System.Windows.Forms.SplitContainer
            $rightSplitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
            $rightSplitContainer.Orientation = [System.Windows.Forms.Orientation]::Horizontal
            # Calculate 1/3 of available height dynamically
            $rightSplitContainer.Add_Resize({
                $totalHeight = $rightSplitContainer.Height - $rightSplitContainer.SplitterWidth
                $rightSplitContainer.SplitterDistance = [Math]::Max(50, [int]($totalHeight / 3))
            })

            # Top of right - Patient/Case details
            $lblDetails = New-Object System.Windows.Forms.Label
            $lblDetails.Text = "Case Details:"
            $lblDetails.Dock = [System.Windows.Forms.DockStyle]::Top
            $lblDetails.Height = 20
            $lblDetails.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)

            $txtDetails = New-Object System.Windows.Forms.TextBox
            $txtDetails.Dock = [System.Windows.Forms.DockStyle]::Fill
            $txtDetails.Multiline = $true
            $txtDetails.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
            $txtDetails.Font = New-Object System.Drawing.Font("Consolas", 9)
            $txtDetails.ReadOnly = $true

            $rightSplitContainer.Panel1.Controls.Add($txtDetails)
            $rightSplitContainer.Panel1.Controls.Add($lblDetails)

            # Bottom of right - split again for Original Text and HL7
            $bottomSplitContainer = New-Object System.Windows.Forms.SplitContainer
            $bottomSplitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
            $bottomSplitContainer.Orientation = [System.Windows.Forms.Orientation]::Horizontal
            # Make the bottom two panels equal (1/2 of remaining 2/3)
            $bottomSplitContainer.Add_Resize({
                $availableHeight = $bottomSplitContainer.Height - $bottomSplitContainer.SplitterWidth
                $bottomSplitContainer.SplitterDistance = [Math]::Max(50, [int]($availableHeight / 2))
            })

            # Original text panel
            $lblOriginalText = New-Object System.Windows.Forms.Label
            $lblOriginalText.Text = "Original Text:"
            $lblOriginalText.Dock = [System.Windows.Forms.DockStyle]::Top
            $lblOriginalText.Height = 20
            $lblOriginalText.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)

            $txtOriginalText = New-Object System.Windows.Forms.TextBox
            $txtOriginalText.Dock = [System.Windows.Forms.DockStyle]::Fill
            $txtOriginalText.Multiline = $true
            $txtOriginalText.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
            $txtOriginalText.Font = New-Object System.Drawing.Font("Consolas", 9)
            $txtOriginalText.ReadOnly = $true
            $txtOriginalText.WordWrap = $false

            $bottomSplitContainer.Panel1.Controls.Add($txtOriginalText)
            $bottomSplitContainer.Panel1.Controls.Add($lblOriginalText)

            # HL7 preview panel
            $lblHL7 = New-Object System.Windows.Forms.Label
            $lblHL7.Text = "HL7 Output Preview:"
            $lblHL7.Dock = [System.Windows.Forms.DockStyle]::Top
            $lblHL7.Height = 20
            $lblHL7.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)

            $txtHL7 = New-Object System.Windows.Forms.TextBox
            $txtHL7.Dock = [System.Windows.Forms.DockStyle]::Fill
            $txtHL7.Multiline = $true
            $txtHL7.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
            $txtHL7.Font = New-Object System.Drawing.Font("Consolas", 9)
            $txtHL7.ReadOnly = $true
            $txtHL7.WordWrap = $false

            $bottomSplitContainer.Panel2.Controls.Add($txtHL7)
            $bottomSplitContainer.Panel2.Controls.Add($lblHL7)

            $rightSplitContainer.Panel2.Controls.Add($bottomSplitContainer)
            $splitContainer.Panel2.Controls.Add($rightSplitContainer)

            # Add fill panel first, top panel last so it sits above
            $converterForm.Controls.Add($splitContainer)
            $converterForm.Controls.Add($topPanel)

            # Dynamic layout for input textbox and Browse button
            $layoutInputRow = {
                $rightMargin = 10

                # Place Browse button flush to the right margin
                $btnBrowseInput.Left = $topPanel.ClientSize.Width - $btnBrowseInput.Width - $rightMargin

                # Textbox fills from left padding to just before the button
                $txtInput.Left  = 10
                $txtInput.Width = [Math]::Max(50, $btnBrowseInput.Left - $txtInput.Left - 10)
            }

            $converterForm.Add_Shown($layoutInputRow)
            $converterForm.Add_Resize($layoutInputRow)

            # Variable to store preview data
            $previewData = $null
            
            # Function to load and preview file
            $loadAndPreview = {
                param([string]$InputPath, [string]$FacilityName)
                
                try {
                    if ([string]::IsNullOrWhiteSpace($InputPath)) {
                        return
                    }
                    
                    if (-not (Test-Path $InputPath)) {
                        [System.Windows.Forms.MessageBox]::Show("Input file not found: $InputPath", "File Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        return
                    }
                    
                    $lblConverterStatus.Text = "Loading..."
                    $lblConverterStatus.ForeColor = [System.Drawing.Color]::Blue
                    $converterForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
                    [System.Windows.Forms.Application]::DoEvents()
                    
                    # Run preview conversion
                    $script:previewData = Convert-PathologyTextToHL7 -InputPath $InputPath -FacilityName $FacilityName -PreviewOnly
                    
                    # Populate cases grid
                    $dgvCases.Columns.Clear()
                    $dgvCases.Rows.Clear()
                    
                    [void]$dgvCases.Columns.Add("CaseNum", "Case #")
                    [void]$dgvCases.Columns.Add("PatientName", "Patient Name")
                    [void]$dgvCases.Columns.Add("MRN", "MRN")
                    [void]$dgvCases.Columns.Add("DOB", "DOB")
                    [void]$dgvCases.Columns.Add("PathReportID", "Path Report ID")
                    [void]$dgvCases.Columns.Add("SpecimenDate", "Specimen Date")
                    [void]$dgvCases.Columns.Add("TextLines", "Text Lines")
                    
                    $dgvCases.Columns[0].Width = 60
                    $dgvCases.Columns[1].Width = 150
                    $dgvCases.Columns[2].Width = 100
                    $dgvCases.Columns[3].Width = 100
                    $dgvCases.Columns[4].Width = 120
                    $dgvCases.Columns[5].Width = 120
                    $dgvCases.Columns[6].Width = 80
                    
                    foreach ($case in $script:previewData.Cases) {
                        $patientName = "$($case.PatientData.NameLast), $($case.PatientData.NameFirst) $($case.PatientData.NameMiddle)".Trim()
                        
                        [void]$dgvCases.Rows.Add(
                            $case.CaseNumber,
                            $patientName,
                            $case.PatientData.MedicalRecordNumber,
                            $case.PatientData.BirthDate,
                            $case.PathReportID,
                            $case.SpecimenDate,
                            $case.TextLines.Count
                        )
                    }
                    
                    $lblConverterStatus.Text = "Ready: $($script:previewData.Cases.Count) cases found"
                    $lblConverterStatus.ForeColor = [System.Drawing.Color]::Green
                    $btnConvert.Enabled = $true
                    
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Error loading file: $($_.Exception.Message)", "Load Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    $lblConverterStatus.Text = "Load failed"
                    $lblConverterStatus.ForeColor = [System.Drawing.Color]::Red
                    $btnConvert.Enabled = $false
                } finally {
                    $converterForm.Cursor = [System.Windows.Forms.Cursors]::Default
                }
            }
            
            # Event: Browse input file
            $btnBrowseInput.Add_Click({
                $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
                $openFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
                $openFileDialog.Title = "Select Input Pathology Text File"
                $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
                
                if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $txtInput.Text = $openFileDialog.FileName
                    # Auto-load and preview
                    & $loadAndPreview -InputPath $txtInput.Text -FacilityName $cmbFacility.SelectedItem.ToString()
                }
            })
            
            # Event: Facility changed - reload if file is already selected
            $cmbFacility.Add_SelectedIndexChanged({
                if (-not [string]::IsNullOrWhiteSpace($txtInput.Text)) {
                    & $loadAndPreview -InputPath $txtInput.Text -FacilityName $cmbFacility.SelectedItem.ToString()
                }
            })
            
            # Event: Case selection changed
            $dgvCases.Add_SelectionChanged({
                if ($dgvCases.SelectedRows.Count -eq 0 -or $null -eq $script:previewData) {
                    return
                }
                
                $selectedRow = $dgvCases.SelectedRows[0]
                $caseNumber = $selectedRow.Cells[0].Value
                
                $case = $script:previewData.Cases | Where-Object { $_.CaseNumber -eq $caseNumber } | Select-Object -First 1
                
                if ($case) {
                    # Show case details
                    $detailsText = @"
Case Number: $($case.CaseNumber)

Patient Information:
  Name: $($case.PatientData.NameLast), $($case.PatientData.NameFirst) $($case.PatientData.NameMiddle)
  MRN: $($case.PatientData.MedicalRecordNumber)
  DOB: $($case.PatientData.BirthDate)
  Sex: $($case.PatientData.Sex)

Case Information:
  Path Report ID: $($case.PathReportID)
  Specimen Date: $($case.SpecimenDate)
  Text Lines: $($case.TextLines.Count)

Facility: $($cmbFacility.SelectedItem)
  Facility Number: $($script:previewData.FacilityConfig.FacilityNum)
  CLIA: $($script:previewData.FacilityConfig.CLIA)
"@
                    $txtDetails.Text = $detailsText
                    
                    # Show original text
                    $txtOriginalText.Text = $case.TextLines -join "`r`n"
                    
                    # Generate HL7 preview for this case
                    $birthDateHL7 = if ($case.PatientData.BirthDate) {
                        try {
                            if ($case.PatientData.BirthDate -match '^\d{2}/\d{2}/\d{2}$') {
                                [DateTime]::ParseExact($case.PatientData.BirthDate, 'MM/dd/yy', $null).ToString('yyyyMMdd')
                            } else {
                                [DateTime]::ParseExact($case.PatientData.BirthDate, 'MM/dd/yyyy', $null).ToString('yyyyMMdd')
                            }
                        } catch { '99999999' }
                    } else { '99999999' }
                    
                    $specimenDateHL7 = if ($case.SpecimenDate) {
                        try {
                            if ($case.SpecimenDate -match '^\d{2}/\d{2}/\d{2}$') {
                                [DateTime]::ParseExact($case.SpecimenDate, 'MM/dd/yy', $null).ToString('yyyyMMdd')
                            } else {
                                [DateTime]::ParseExact($case.SpecimenDate, 'MM/dd/yyyy', $null).ToString('yyyyMMdd')
                            }
                        } catch { '99999999' }
                    } else { '99999999' }
                    
                    $hl7Lines = @()
                    $hl7Lines += "MSH|^~\&|E-Path Case=$($case.CaseNumber)|$($script:previewData.FacilityConfig.CLIA)|E-Path|NHSCR|99999999||ORU^R01^ORU_R01||P|2.5.1|||||USA||ENG||VOL_V_40_ORU_R01^NAACCR_CP"
                    $hl7Lines += "PID|1||$($case.PatientData.MedicalRecordNumber)^^^^MR^~^^^^SS||$($case.PatientData.NameLast)^$($case.PatientData.NameFirst)^$($case.PatientData.NameMiddle)||$birthDateHL7|$($case.PatientData.Sex)|||Unknown^^Unknown^ZZ^99999|||"
                    $hl7Lines += "OBR|1||$($case.PathReportID)||||$specimenDateHL7|||||||||^physicianNameLast^physicianNameFirst^physicianNameMiddle|||||||||F||||||||"
                    
                    for ($i = 0; $i -lt $case.TextLines.Count; $i++) {
                        $hl7Lines += "OBX|$($i + 1)|TX|||$($case.TextLines[$i])"
                    }
                    
                    $txtHL7.Text = $hl7Lines -join "`r`n"
                }
            })
            
            # Event: Convert button
            $btnConvert.Add_Click({
                if ($null -eq $script:previewData) {
                    [System.Windows.Forms.MessageBox]::Show("No file loaded. Please select a file first.", "No Data", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                
                # Ask for output file location
                $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
                $saveFileDialog.Filter = "HL7 files (*.hl7)|*.hl7|All files (*.*)|*.*"
                $saveFileDialog.Title = "Save HL7 Output File"
                $saveFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
                
                # Suggest default filename based on input
                $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($txtInput.Text)
                $facilityNum = $script:previewData.FacilityConfig.FacilityNum
                $defaultName = "${inputFileName}_${facilityNum}.hl7"
                $saveFileDialog.FileName = $defaultName
                
                if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    try {
                        $lblConverterStatus.Text = "Converting..."
                        $lblConverterStatus.ForeColor = [System.Drawing.Color]::Blue
                        $converterForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
                        [System.Windows.Forms.Application]::DoEvents()
                        
                        # Run actual conversion
                        $result = Convert-PathologyTextToHL7 -InputPath $txtInput.Text -OutputPath $saveFileDialog.FileName -FacilityName $cmbFacility.SelectedItem.ToString()
                        
                        $lblConverterStatus.Text = "Conversion complete: $($result.Cases.Count) cases written to HL7"
                        $lblConverterStatus.ForeColor = [System.Drawing.Color]::Green
                        
                        $message = @"
Text conversion complete!

Cases processed: $($result.Cases.Count)
Output file: $($saveFileDialog.FileName)

Open the output file location?
"@
                        
                        $dialogResult = [System.Windows.Forms.MessageBox]::Show($message, "Conversion Complete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
                        
                        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                            Start-Process "explorer.exe" -ArgumentList "/select,`"$($saveFileDialog.FileName)`""
                        }
                        
                    } catch {
                        [System.Windows.Forms.MessageBox]::Show("Error during conversion: $($_.Exception.Message)", "Conversion Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        $lblConverterStatus.Text = "Conversion failed"
                        $lblConverterStatus.ForeColor = [System.Drawing.Color]::Red
                    } finally {
                        $converterForm.Cursor = [System.Windows.Forms.Cursors]::Default
                    }
                }
            })
            
            [void]$converterForm.ShowDialog()
            
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error opening txt converter: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}
