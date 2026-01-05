function Export-SelectedHl7 {
    param(
        [int]$MessageIndex,
        [array]$Hl7Messages,
        [string]$OutputPath
    )

    if ($MessageIndex -lt 0 -or $MessageIndex -ge $Hl7Messages.Count) {
        return @{ Success = $false; Message = "Invalid message index: $MessageIndex" }
    }

    try {
        $message = $Hl7Messages[$MessageIndex]
        $rawContent = $message.RawContent

        # Write HL7 message to file with ASCII encoding and no trailing newline
        Set-Content -Path $OutputPath -Value $rawContent -Encoding ASCII -NoNewline

        return @{
            Success = $true
            ExportedCount = 1
            Errors = @()
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

