# export-csv.ps1
# Export tumors to CSV format (selected or all)

function Export-TumorsCsv {
    <#
    .SYNOPSIS
    Export tumors to CSV format.

    .PARAMETER TumorIndices
    Optional array of tumor indices to export. If not provided, exports all tumors.

    .PARAMETER XmlDoc
    The XML document containing the tumors.

    .PARAMETER NsMgr
    The namespace manager for XPath queries.

    .PARAMETER OutputPath
    The path to write the CSV file.

    .PARAMETER FieldList
    Array of NAACCR field IDs to include in the export.

    .PARAMETER CustomFields
    Optional hashtable mapping custom field IDs to their parent elements.
    #>
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath,
        [array]$FieldList,
        [hashtable]$CustomFields = @{}
    )

    # If no indices provided, export all tumors
    if ($null -eq $TumorIndices -or $TumorIndices.Count -eq 0) {
        if ($script:Tumors.Count -eq 0) {
            return @{ Success = $false; Message = "No tumors available for export."; ExportedCount = 0; Errors = @() }
        }
        $TumorIndices = @(0..($script:Tumors.Count - 1))
    }

    $errors = @()
    $rows = @()

    try {
        # Build CSV rows - one row per tumor
        foreach ($tumorIndex in $TumorIndices) {
            if ($tumorIndex -lt 0 -or $tumorIndex -ge $script:Tumors.Count) {
                $errors += "Invalid tumor index: $tumorIndex"
                continue
            }

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

                # Use dynamic parent element lookup from dictionary
                $parentElement = Get-NaaccrParentElement -XmlId $fieldId -CustomFields $CustomFields

                if ($parentElement -eq "Patient") {
                    $node = $patient.SelectSingleNode("./n:Item[@naaccrId='$fieldId']", $NsMgr)
                    if ($null -ne $node) {
                        $value = $node.InnerText
                    }
                }
                else {
                    # Tumor-level or NaaccrData-level fields (treat NaaccrData as tumor context)
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

# Backward compatibility aliases
function Export-SelectedCsv {
    param(
        [array]$TumorIndices,
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath,
        [array]$FieldList,
        [hashtable]$CustomFields = @{}
    )

    return Export-TumorsCsv @PSBoundParameters
}

function Export-AllCsv {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$OutputPath,
        [array]$FieldList,
        [hashtable]$CustomFields = @{}
    )

    return Export-TumorsCsv -XmlDoc $XmlDoc -NsMgr $NsMgr -OutputPath $OutputPath -FieldList $FieldList -CustomFields $CustomFields
}
