# concatenate-txt.ps1
# Text file concatenation utilities

function Get-TxtFileInfo {
    param(
        [string]$FilePath
    )

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8

        # Count lines
        $lineCount = ($content -split "`r`n|`n|`r").Count

        # Get file size
        $fileInfo = Get-Item $FilePath
        $fileSize = $fileInfo.Length

        return @{
            Success = $true
            LineCount = $lineCount
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

function Get-TxtFilePreview {
    param(
        [string]$Content,
        [int]$MaxLines = 50
    )

    # Split by lines
    $lines = $Content -split "`r`n|`n|`r"

    $preview = @()
    $count = [Math]::Min($lines.Count, $MaxLines)

    for ($i = 0; $i -lt $count; $i++) {
        $line = $lines[$i]
        $preview += [PSCustomObject]@{
            LineNumber = $i + 1
            LineContent = if ($line.Length -gt 200) { $line.Substring(0, 200) + "..." } else { $line }
        }
    }

    return $preview
}

function Write-ConcatenatedTxt {
    param(
        [array]$FileInfos,
        [string]$OutputPath
    )

    $combinedContent = ""

    foreach ($item in $FileInfos) {
        $content = $item.Info.Content

        # Append the content
        $combinedContent += $content

        # Add a blank line separator between files (ensure content ends with newline first)
        if (-not $content.EndsWith("`r`n") -and -not $content.EndsWith("`n") -and -not $content.EndsWith("`r")) {
            $combinedContent += "`r`n`r`n"
        } else {
            # Content already ends with newline, just add one more for separator
            $combinedContent += "`r`n"
        }
    }

    # Write with UTF8 encoding
    Set-Content -Path $OutputPath -Value $combinedContent -Encoding UTF8 -NoNewline
}
