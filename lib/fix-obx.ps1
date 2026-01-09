# fix-obx.ps1
# Utility to fix truncated OBX segments in HL7 messages by padding with pipes

function Fix-ObxInMessages {
    param(
        [array]$Hl7Messages,
        [int]$MinFields = 5  # Minimum number of fields (pipe separators) for OBX
    )
    
    $fixedCount = 0
    $totalObxCount = 0
    $modifiedMessages = @()
    
    foreach ($message in $Hl7Messages) {
        $rawContent = $message.RawContent
        $lines = $rawContent -split "`n"
        $modifiedLines = @()
        
        foreach ($line in $lines) {
            $trimmedLine = $line.TrimEnd("`r")
            
            # Check if this is an OBX segment
            if ($trimmedLine.StartsWith("OBX|")) {
                $totalObxCount++
                
                # Count the number of pipe delimiters
                $pipeCount = ($trimmedLine.ToCharArray() | Where-Object { $_ -eq '|' }).Count
                
                # If fewer pipes than minimum, pad with pipes
                if ($pipeCount -lt $MinFields) {
                    $pipesToAdd = $MinFields - $pipeCount
                    $trimmedLine = $trimmedLine + ('|' * $pipesToAdd)
                    $fixedCount++
                }
            }
            
            $modifiedLines += $trimmedLine
        }
        
        # Rejoin lines with newline
        $modifiedContent = $modifiedLines -join "`n"
        $modifiedMessages += $modifiedContent
    }
    
    # Combine all messages
    $combinedContent = $modifiedMessages -join "`n"
    
    return @{
        ModifiedContent = $combinedContent
        FixedCount = $fixedCount
        TotalObxCount = $totalObxCount
    }
}

