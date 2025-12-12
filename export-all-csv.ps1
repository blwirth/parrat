# export-all-csv.ps1
# Export all tumors to CSV format

function Export-AllCsv {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath,
        [array]$FieldList
    )

    if ($script:Tumors.Count -eq 0) {
        return @{ Success = $false; Message = "No tumors available for export."; ExportedCount = 0; Errors = @() }
    }

    $errors = @()
    $rows = @()

    try {
        # Build CSV rows - one row per tumor
        for ($tumorIndex = 0; $tumorIndex -lt $script:Tumors.Count; $tumorIndex++) {
            $tumor = $script:Tumors[$tumorIndex]
            $patient = $tumor.SelectSingleNode("ancestor::n:Patient[1]", $NsMgr)

            if ($null -eq $patient) {
                $errors += "Tumor at index $tumorIndex has no parent Patient node"
                continue
            }

            # Build row data
            $row = @{}
            
            foreach ($fieldId in $FieldList) {
                $value = ""
                
                # Check if field is at patient level or tumor level
                # Patient-level fields
                $patientFields = @("patientIdNumber", "nameLast", "nameFirst", "nameMiddle", "dateOfBirth", "reportingFacility")
                
                if ($patientFields -contains $fieldId) {
                    $node = $patient.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                    if ($null -ne $node) {
                        $value = $node.InnerText
                    }
                }
                else {
                    # Tumor-level fields
                    $node = $tumor.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                    if ($null -ne $node) {
                        $value = $node.InnerText
                    }
                }
                
                $row[$fieldId] = $value
            }
            
            $rows += $row
        }

        # Write CSV file
        $csvContent = @()
        
        # Header row
        $headerRow = $FieldList -join ","
        $csvContent += $headerRow
        
        # Data rows
        foreach ($row in $rows) {
            $csvRow = @()
            foreach ($fieldId in $FieldList) {
                $value = $row[$fieldId]
                if ($null -eq $value) {
                    $value = ""
                }
                # Escape commas, quotes, and newlines in CSV
                if ($value -match '[,"\r\n]') {
                    $value = '"' + ($value -replace '"', '""') + '"'
                }
                $csvRow += $value
            }
            $csvContent += $csvRow -join ","
        }
        
        # Write to file with UTF-8 encoding
        [System.IO.File]::WriteAllLines($OutputPath, $csvContent, [System.Text.Encoding]::UTF8)

        return @{
            Success = ($errors.Count -eq 0)
            ExportedCount = $rows.Count
            Errors = $errors
        }
    }
    catch {
        return @{
            Success = $false
            ExportedCount = 0
            Errors = @("Error during export: $($_.Exception.Message)")
        }
    }
}
