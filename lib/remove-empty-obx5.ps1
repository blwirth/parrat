# remove-empty-obx5.ps1
# Utility to remove OBX segments with empty OBX-5 (Observation Value) field

function Remove-EmptyObx5FromMessages {
    param(
        [array]$Hl7Messages
    )

    $removedCount = 0
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

                # Split by pipe to get fields (0-indexed)
                # Field 5 (index 5) is OBX-5 (Observation Value)
                $fields = $trimmedLine -split '\|', 7

                # Check if OBX-5 is empty or whitespace (index 5, but array may be shorter)
                $obx5Value = if ($fields.Count -gt 5) { $fields[5] } else { "" }

                # Skip this line if OBX-5 is empty or whitespace
                if ([string]::IsNullOrWhiteSpace($obx5Value)) {
                    $removedCount++
                    continue
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
        RemovedCount = $removedCount
        TotalObxCount = $totalObxCount
    }
}

function Remove-EmptyObx5FromRawContent {
    <#
    .SYNOPSIS
    High-performance version that processes raw file content directly.
    Use this for very large files to avoid message parsing overhead.
    #>
    param(
        [string]$RawContent
    )

    $removedCount = 0
    $totalObxCount = 0

    # Normalize line endings
    $RawContent = $RawContent -replace "`r`n", "`n"
    $RawContent = $RawContent -replace "`r", "`n"

    $lines = $RawContent -split "`n"
    $lineCount = $lines.Count

    # Pre-allocate array for results (much faster than List for known size, but we'll use List since size may change)
    $result = [System.Collections.Generic.List[string]]::new($lineCount)

    for ($i = 0; $i -lt $lineCount; $i++) {
        $line = $lines[$i]

        # Fast OBX check
        if ($line.Length -ge 4 -and $line.Substring(0, 4) -eq "OBX|") {
            $totalObxCount++

            # Split by pipe to get fields
            # Use a limit to avoid unnecessary splits, but we need at least 6 fields to check OBX-5
            $fields = $line -split '\|', 7

            # Check if OBX-5 is empty or whitespace (index 5)
            $obx5Value = if ($fields.Count -gt 5) { $fields[5] } else { "" }

            # Skip this line if OBX-5 is empty or whitespace
            if ([string]::IsNullOrWhiteSpace($obx5Value)) {
                $removedCount++
                continue
            }
        }

        $result.Add($line)
    }

    return @{
        ModifiedContent = [string]::Join("`n", $result)
        RemovedCount = $removedCount
        TotalObxCount = $totalObxCount
    }
}

