# export-selected-hl7-csv.ps1
# Export selected HL7 messages to CSV format

function Export-SelectedHl7Csv {
    param(
        [array]$MessageIndices,
        [array]$Hl7Messages,
        [string]$OutputPath
    )

    if ($MessageIndices.Count -eq 0) {
        return @{ Success = $false; Message = "No messages selected for export."; ExportedCount = 0; Errors = @() }
    }

    $errors = @()
    $rows = @()

    try {
        # Build CSV rows - one row per message
        foreach ($messageIndex in $MessageIndices) {
            if ($messageIndex -lt 0 -or $messageIndex -ge $Hl7Messages.Count) {
                $errors += "Invalid message index: $messageIndex"
                continue
            }

            $message = $Hl7Messages[$messageIndex]

            # Extract fields: last name, first name, date of birth, message date/time (MSH-7)
            $lastName = if ($message.PatientLastName) { $message.PatientLastName } else { "" }
            $firstName = if ($message.PatientFirstName) { $message.PatientFirstName } else { "" }
            $dateOfBirth = if ($message.DateOfBirth) { $message.DateOfBirth } else { "" }
            $messageDateTime = if ($message.MessageDateTime) { $message.MessageDateTime } else { "" }

            $row = @{
                LastName = $lastName
                FirstName = $firstName
                DateOfBirth = $dateOfBirth
                MessageDateTime = $messageDateTime
            }
            
            $rows += $row
        }

        # Write CSV file
        $csvContent = @()
        
        # Header row
        $headerRow = "LastName,FirstName,DateOfBirth,MessageDateTime"
        $csvContent += $headerRow
        
        # Data rows
        foreach ($row in $rows) {
            $csvRow = @()
            
            # Add each field value
            $fields = @($row.LastName, $row.FirstName, $row.DateOfBirth, $row.MessageDateTime)
            foreach ($value in $fields) {
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


