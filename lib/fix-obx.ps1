# fix-obx.ps1
# Utility to fix truncated OBX segments in HL7 messages by padding with pipes

function Fix-ObxInMessages {
    param(
        [array]$Hl7Messages,
        [int]$MinFields = 5  # Minimum number of fields (pipe separators) for OBX
    )
    
    $fixedCount = 0
    $totalObxCount = 0
    
    # Use StringBuilder for efficient string concatenation
    $sb = New-Object System.Text.StringBuilder
    $isFirst = $true
    
    foreach ($message in $Hl7Messages) {
        $rawContent = $message.RawContent
        $lines = $rawContent -split "`n"
        
        # Use List<string> for efficient appending
        $modifiedLines = [System.Collections.Generic.List[string]]::new($lines.Count)
        
        foreach ($line in $lines) {
            $trimmedLine = $line.TrimEnd("`r")
            
            # Check if this is an OBX segment (fast string check)
            if ($trimmedLine.Length -ge 4 -and $trimmedLine.Substring(0, 4) -eq "OBX|") {
                $totalObxCount++
                
                # Fast pipe counting using IndexOf loop
                $pipeCount = 0
                $idx = -1
                while (($idx = $trimmedLine.IndexOf('|', $idx + 1)) -ne -1) {
                    $pipeCount++
                }
                
                # Pad if needed
                if ($pipeCount -lt $MinFields) {
                    $pipesToAdd = $MinFields - $pipeCount
                    $trimmedLine = $trimmedLine + (New-Object string('|', $pipesToAdd))
                    $fixedCount++
                }
            }
            
            $modifiedLines.Add($trimmedLine)
        }
        
        # Join lines for this message
        $modifiedContent = [string]::Join("`n", $modifiedLines)
        
        # Append to StringBuilder
        if (-not $isFirst) {
            [void]$sb.Append("`n")
        }
        [void]$sb.Append($modifiedContent)
        $isFirst = $false
    }
    
    return @{
        ModifiedContent = $sb.ToString()
        FixedCount = $fixedCount
        TotalObxCount = $totalObxCount
    }
}

function Fix-ObxInRawContent {
    <#
    .SYNOPSIS
    High-performance version that processes raw file content directly.
    Use this for very large files to avoid message parsing overhead.
    #>
    param(
        [string]$RawContent,
        [int]$MinFields = 5
    )
    
    $fixedCount = 0
    $totalObxCount = 0
    
    # Normalize line endings
    $RawContent = $RawContent -replace "`r`n", "`n"
    $RawContent = $RawContent -replace "`r", "`n"
    
    $lines = $RawContent -split "`n"
    $lineCount = $lines.Count
    
    # Pre-allocate array for results (much faster than List for known size)
    $result = New-Object string[] $lineCount
    
    for ($i = 0; $i -lt $lineCount; $i++) {
        $line = $lines[$i]
        
        # Fast OBX check
        if ($line.Length -ge 4 -and $line.Substring(0, 4) -eq "OBX|") {
            $totalObxCount++
            
            # Fast pipe counting
            $pipeCount = 0
            $idx = -1
            while (($idx = $line.IndexOf('|', $idx + 1)) -ne -1) {
                $pipeCount++
            }
            
            if ($pipeCount -lt $MinFields) {
                $pipesToAdd = $MinFields - $pipeCount
                $line = $line + (New-Object string('|', $pipesToAdd))
                $fixedCount++
            }
        }
        
        $result[$i] = $line
    }
    
    return @{
        ModifiedContent = [string]::Join("`n", $result)
        FixedCount = $fixedCount
        TotalObxCount = $totalObxCount
    }
}
