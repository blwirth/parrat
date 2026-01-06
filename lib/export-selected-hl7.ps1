function Export-SelectedHl7 {
    param(
        [array]$MessageIndices,
        [array]$Hl7Messages,
        [string]$OutputPath
    )

    if ($MessageIndices.Count -eq 0) {
        return @{ Success = $false; Message = "No messages selected for export."; ExportedCount = 0; Errors = @() }
    }

    $errors = @()
    $exportedMessages = @()

    try {
        foreach ($messageIndex in $MessageIndices) {
            if ($messageIndex -lt 0 -or $messageIndex -ge $Hl7Messages.Count) {
                $errors += "Invalid message index: $messageIndex"
                continue
            }

            $message = $Hl7Messages[$messageIndex]
            $exportedMessages += $message.RawContent
        }

        if ($exportedMessages.Count -eq 0) {
            return @{
                Success = $false
                ExportedCount = 0
                Errors = $errors
            }
        }

        # Concatenate messages directly (no separator needed - MSH| at start of each message identifies boundaries)
        $combinedContent = $exportedMessages -join ""

        # Write HL7 messages to file with ASCII encoding and no trailing newline
        Set-Content -Path $OutputPath -Value $combinedContent -Encoding ASCII -NoNewline

        return @{
            Success = ($errors.Count -eq 0)
            ExportedCount = $exportedMessages.Count
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

