# split-hl7-at-positions.ps1
# Script to split an HL7 file at multiple specified message positions
# Usage: 
#   .\split-hl7-at-positions.ps1 -FilePath "path\to\your\file.hl7" -SplitPositions @(50, 100)
#   .\split-hl7-at-positions.ps1 (will prompt for file path and split positions)
#   The number entered will be the first message number in the new file, e.g., if 50 is entered, file 1 will contain messages 1-49, and file 2 will contain messages 50 through the end of the file.

param(
    [Parameter(Mandatory=$false)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$false)]
    [int[]]$SplitPositions = @()
)

# Function to get a valid file path
function Get-ValidFilePath {
    $filePathPrompt = Read-Host "Enter the full file path (e.g., 'C:\path\to\file.hl7') or type 'browse' to select the file"
    
    if ($filePathPrompt -eq "browse") {
        try {
            # Try to use the more reliable Out-GridView method first
            $fileBrowser = New-Object -ComObject Microsoft.Office.Interop.Excel.Application
            $fileBrowser.Visible = $false
            $fileBrowser.DisplayAlerts = $false
            
            $fileDialog = $fileBrowser.FileDialog([Microsoft.Office.Interop.Excel.XlFileDialogType]::xlFileDialogOpen)
            $fileDialog.Title = "Select an HL7 File"
            $fileDialog.AllowMultiSelect = $false
            
            # Set filter for HL7 files
            $fileDialog.Filters.Clear()
            $fileDialog.Filters.Add("HL7 Files", "*.hl7")
            $fileDialog.Filters.Add("All Files", "*.*")
            
            if ($fileDialog.Show() -eq -1) {
                $selectedFile = $fileDialog.SelectedItems.Item(1)
                $fileBrowser.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($fileBrowser) | Out-Null
                return $selectedFile
            } else {
                $fileBrowser.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($fileBrowser) | Out-Null
                Write-Host "No file selected. Please try again."
                return Get-ValidFilePath
            }
        } catch {
            # Fallback to PowerShell script method if COM object fails
            Write-Host "Using alternative file browser method..."
            
            # Create a temporary script to launch a file dialog
            $tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
            
            @'
Add-Type -AssemblyName System.Windows.Forms
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*"
$openFileDialog.Title = "Select an HL7 File"
$openFileDialog.ShowHelp = $true
$openFileDialog.Multiselect = $false

if ($openFileDialog.ShowDialog() -eq "OK") {
    $openFileDialog.FileName | Out-File -FilePath "$env:TEMP\selected_file.txt" -Encoding utf8
}
'@ | Out-File -FilePath $tempFile -Encoding utf8
            
            # Run the script in a new PowerShell process
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`"" -Wait
            
            # Check if a file was selected
            $selectedFilePath = "$env:TEMP\selected_file.txt"
            if (Test-Path $selectedFilePath) {
                $selectedFile = Get-Content $selectedFilePath -Raw
                Remove-Item $selectedFilePath -Force
                Remove-Item $tempFile -Force
                
                if ([string]::IsNullOrWhiteSpace($selectedFile)) {
                    Write-Host "No file selected. Please try again."
                    return Get-ValidFilePath
                }
                
                return $selectedFile.Trim()
            } else {
                Remove-Item $tempFile -Force
                Write-Host "No file selected. Please try again."
                return Get-ValidFilePath
            }
        }
    } else {
        # Remove any quotes that might have been added
        $filePathPrompt = $filePathPrompt -replace "^[`"']|[`"']$", ""
        
        # Check if path is valid
        if (Test-Path $filePathPrompt) {
            return $filePathPrompt
        } else {
            # Try to fix common path issues
            if ($filePathPrompt -match "^C:(?!\\)") {
                $correctedPath = $filePathPrompt -replace "^C:", "C:\"
                if (Test-Path $correctedPath) {
                    Write-Host "Corrected path to: $correctedPath"
                    return $correctedPath
                }
            }
            
            Write-Host "The specified file does not exist: $filePathPrompt"
            Write-Host "Please check the path and try again."
            return Get-ValidFilePath
        }
    }
}

# Function to get valid split positions
function Get-ValidSplitPositions {
    $positionsInput = Read-Host "Enter the message positions to split at (e.g., '50,100' to split at messages 50 and 100)"
    
    try {
        # Parse the input string into an array of integers
        $positions = $positionsInput -split ',' | ForEach-Object { [int]$_.Trim() }
        
        # Ensure positions are unique and sorted
        $positions = $positions | Sort-Object -Unique
        
        if ($positions.Count -eq 0) {
            Write-Host "No valid positions entered. Please try again."
            return Get-ValidSplitPositions
        }
        
        return $positions
    } catch {
        Write-Host "Invalid input. Please enter numbers separated by commas."
        return Get-ValidSplitPositions
    }
}

# If parameters are not provided, prompt the user
if (-not $FilePath) {
    $FilePath = Get-ValidFilePath
}

# Verify file exists (in case it was provided as a parameter)
if (-not (Test-Path $FilePath)) {
    Write-Error "The specified file does not exist: $FilePath"
    exit 1
}

if ($SplitPositions.Count -eq 0) {
    $SplitPositions = Get-ValidSplitPositions
}

# Sort the split positions to ensure they're in ascending order
$SplitPositions = $SplitPositions | Sort-Object -Unique

# Get file information for naming output files
$fileInfo = Get-Item $FilePath
$baseName = $fileInfo.BaseName
$extension = $fileInfo.Extension
$directory = $fileInfo.DirectoryName

# Read the file content
$content = Get-Content -Path $FilePath -Raw

# Split the content by MSH marker at the beginning of a line
$messages = $content -split "(?m)^MSH\|"

# Remove any empty messages (could happen if the file starts with MSH)
$messages = $messages | Where-Object { $_ -match '\S' }

# Ensure we have enough messages for the requested split positions
$maxSplitPosition = ($SplitPositions | Measure-Object -Maximum).Maximum
if ($messages.Count -lt $maxSplitPosition) {
    Write-Error "The file only contains $($messages.Count) messages, but you requested to split at position $maxSplitPosition"
    exit 1
}

Write-Host "File contains $($messages.Count) messages total."
Write-Host "Will split at positions: $($SplitPositions -join ', ')"

# Add a position at the end to simplify the loop
$SplitPositions += $messages.Count + 1

# Create the output files
$startPos = 1
$filesCreated = 0

for ($i = 0; $i -lt $SplitPositions.Count; $i++) {
    $endPos = $SplitPositions[$i] - 1
    
    # Skip if start position is greater than end position
    if ($startPos -gt $endPos) {
        $startPos = $SplitPositions[$i]
        continue
    }
    
    # Extract the messages for this chunk
    $chunkMessages = $messages[($startPos - 1)..($endPos - 1)]
    
    # Create the output file path
    $outputFilePath = Join-Path $directory "$($baseName)_$($startPos)-$($endPos)$extension"
    
    # Add MSH| back to the beginning of each message (except possibly the first one if it already has it)
    $processedMessages = @()
    for ($j = 0; $j -lt $chunkMessages.Count; $j++) {
        if ($j -eq 0 -and $startPos -eq 1 -and $chunkMessages[$j].StartsWith("MSH|")) {
            # First message in the file might already have MSH|
            $processedMessages += $chunkMessages[$j]
        } else {
            $processedMessages += "MSH|" + $chunkMessages[$j]
        }
    }
    
    # Join the messages and write to the output file without adding extra newlines
    $chunkContent = $processedMessages -join ""
    Set-Content -Path $outputFilePath -Value $chunkContent -Encoding ASCII -NoNewline
    
    Write-Host "Created file with messages $startPos-$endPos`: $outputFilePath"
    $filesCreated++
    
    # Update the start position for the next chunk
    $startPos = $SplitPositions[$i]
}

Write-Host "`nOriginal file was not modified and remains intact at: $FilePath"
Write-Host "Split complete. Created $filesCreated files." 