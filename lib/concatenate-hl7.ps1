# concatenate-hl7.ps1
# NAACCR HL7 concatenation utilities

. "$PSScriptRoot\syntax-helpers.ps1"

function Get-Hl7FileInfo {
    param(
        [string]$FilePath
    )

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding ASCII

        # Count messages (MSH| at start of line)
        $messageCount = ([regex]::Matches($content, "(?m)^MSH\|")).Count

        # Get file size
        $fileInfo = Get-Item $FilePath
        $fileSize = $fileInfo.Length

        return @{
            Success = $true
            MessageCount = $messageCount
            FileSize = $fileSize
            Content = $content
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-Hl7MessagePreview {
    param(
        [string]$Content,
        [int]$MaxMessages = 50
    )

    # Split by MSH| at start of line
    $messages = $Content -split "(?m)^MSH\|"
    $messages = $messages | Where-Object { $_ -match '\S' }

    $preview = @()
    $count = [Math]::Min($messages.Count, $MaxMessages)

    for ($i = 0; $i -lt $count; $i++) {
        $msg = $messages[$i]
        if (-not $msg.StartsWith("MSH|")) {
            $msg = "MSH|" + $msg
        }

        # Extract PID segment for patient info (if present)
        $pidMatch = [regex]::Match($msg, "(?m)^PID\|([^\r\n]+)")
        $pidLine = if ($pidMatch.Success) { $pidMatch.Groups[1].Value } else { "" }

        # Extract MSH segment for message type
        $mshMatch = [regex]::Match($msg, "(?m)^MSH\|([^\r\n]+)")
        $mshLine = if ($mshMatch.Success) { $mshMatch.Groups[1].Value } else { "" }

        # Parse PID fields (field 5 is patient name, field 3 is patient ID)
        $pidFields = if ($pidLine) { $pidLine -split '\|' } else { @() }
        $patientName = if ($pidFields.Count -gt 5) { $pidFields[5] } else { "" }
        $patientId = if ($pidFields.Count -gt 3) { $pidFields[3] } else { "" }

        # Parse MSH fields (field 9 is message type)
        $mshFields = if ($mshLine) { $mshLine -split '\|' } else { @() }
        $messageType = if ($mshFields.Count -gt 9) { $mshFields[9] } else { "" }

        $preview += [PSCustomObject]@{
            MessageIndex = $i + 1
            MessageType = $messageType
            PatientId = $patientId
            PatientName = $patientName
            Preview = if ($msg.Length -gt 200) { $msg.Substring(0, 200) + "..." } else { $msg }
        }
    }

    return $preview
}

function Write-ConcatenatedHl7 {
    param(
        [array]$FileInfos,
        [string]$OutputPath,
        [switch]$ShowProgress
    )

    # Use StreamWriter for efficient file writing - avoids O(n²) string concatenation
    $stream = $null
    try {
        $stream = New-Object System.IO.StreamWriter($OutputPath, $false, [System.Text.Encoding]::ASCII)
        $needsNewline = $false
        $totalFiles = $FileInfos.Count
        $currentFile = 0

        foreach ($item in $FileInfos) {
            $currentFile++

            if ($ShowProgress -and ($currentFile % 100 -eq 0 -or $currentFile -eq $totalFiles)) {
                Write-Progress -Activity "Concatenating HL7 files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
            }

            # Support both cached content and streaming from file path
            $content = if ($null -ne $item.Info -and $null -ne $item.Info.Content) {
                $item.Info.Content
            } elseif ($null -ne $item.FilePath -and (Test-Path $item.FilePath)) {
                Get-Content -Path $item.FilePath -Raw -Encoding ASCII
            } else {
                $null
            }

            if ([string]::IsNullOrEmpty($content)) { continue }

            # Trim trailing whitespace from content
            $trimmedContent = $content.TrimEnd("`r", "`n")
            if ([string]::IsNullOrEmpty($trimmedContent)) { continue }

            # Add newline separator between files to prevent MSH| from concatenating onto previous OBX
            if ($needsNewline) {
                $stream.Write("`r`n")
            }

            $stream.Write($trimmedContent)
            $needsNewline = $true
        }

        if ($ShowProgress) {
            Write-Progress -Activity "Concatenating HL7 files" -Completed
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Close()
            $stream.Dispose()
        }
    }
}

function Write-ConcatenatedHl7FromPaths {
    param(
        [string[]]$FilePaths,
        [string]$OutputPath
    )

    # Ultra-fast streaming mode - reads directly from files, no preview/caching
    # Use for very large batches (1000+ files)
    $stream = $null
    try {
        $stream = New-Object System.IO.StreamWriter($OutputPath, $false, [System.Text.Encoding]::ASCII)
        $needsNewline = $false
        $totalFiles = $FilePaths.Count
        $currentFile = 0

        foreach ($filePath in $FilePaths) {
            $currentFile++

            if ($currentFile % 100 -eq 0 -or $currentFile -eq $totalFiles) {
                Write-Progress -Activity "Concatenating HL7 files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
            }

            if (-not (Test-Path $filePath)) { continue }

            $content = Get-Content -Path $filePath -Raw -Encoding ASCII
            if ([string]::IsNullOrEmpty($content)) { continue }

            $trimmedContent = $content.TrimEnd("`r", "`n")
            if ([string]::IsNullOrEmpty($trimmedContent)) { continue }

            if ($needsNewline) {
                $stream.Write("`r`n")
            }

            $stream.Write($trimmedContent)
            $needsNewline = $true
        }

        Write-Progress -Activity "Concatenating HL7 files" -Completed

        return @{
            Success = $true
            FilesProcessed = $currentFile
            OutputPath = $OutputPath
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Close()
            $stream.Dispose()
        }
    }
}
