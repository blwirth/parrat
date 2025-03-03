# split-hl7-file-with-error.ps1
# Script to split an HL7 file based on an error message number
# Usage: 
#   .\split-hl7-file-with-error.ps1 -FilePath "path\to\your\file.hl7" -ErrorMessageNumber 51 -SplitFile $true

param(
    [Parameter(Mandatory=$false)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$false)]
    [int]$ErrorMessageNumber,
    
    [Parameter(Mandatory=$false)]
    [bool]$SplitFile = $true
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

# If parameters are not provided, prompt the user
if (-not $FilePath) {
    $FilePath = Get-ValidFilePath
}

# Verify file exists (in case it was provided as a parameter)
if (-not (Test-Path $FilePath)) {
    Write-Error "The specified file does not exist: $FilePath"
    exit 1
}

if (-not $ErrorMessageNumber) {
    $validInput = $false
    while (-not $validInput) {
        try {
            $ErrorMessageNumber = [int](Read-Host "What is the error message number (e.g., 51)?")
            $validInput = $true
        } catch {
            Write-Host "Please enter a valid number."
        }
    }
}

if (-not $PSBoundParameters.ContainsKey('SplitFile')) {
    $splitPrompt = Read-Host "Do you want to split the file into two files? This is recommended for faster processing. (Y/N, default: Y)"
    $SplitFile = ($splitPrompt -eq "" -or $splitPrompt.ToLower() -eq "y")
}

# Get file information for naming output files
$fileInfo = Get-Item $FilePath
$baseName = $fileInfo.BaseName
$extension = $fileInfo.Extension
$directory = $fileInfo.DirectoryName

# Output file paths
$errorFilePath = Join-Path $directory "$($baseName)_$($ErrorMessageNumber)_removed$extension"
$remainingFilePath = Join-Path $directory "$($baseName)_$($ErrorMessageNumber+1)-remaining$extension"
$cleanFilePath = Join-Path $directory "$($baseName)_clean$extension"

# Read the file content
$content = Get-Content -Path $FilePath -Raw

# Split the content by MSH marker (which indicates the start of a new message)
$messages = $content -split "(?=MSH\|)"

# Remove any empty messages (could happen if the file starts with MSH)
$messages = $messages | Where-Object { $_ -match '\S' }

# Ensure we have enough messages
if ($messages.Count -lt $ErrorMessageNumber) {
    Write-Error "The file only contains $($messages.Count) messages, but error is reported at message $ErrorMessageNumber"
    exit 1
}

Write-Host "File contains $($messages.Count) messages total."

# Extract the error message (index is 0-based, so subtract 1)
$errorMessage = $messages[$ErrorMessageNumber - 1]
if (-not $errorMessage.StartsWith("MSH|")) {
    $errorMessage = "MSH|" + $errorMessage
}

if ($SplitFile) {
    # Extract remaining messages
    $remainingMessages = $messages[$ErrorMessageNumber..($messages.Count - 1)]
    
    # Write the error message to its own file
    Set-Content -Path $errorFilePath -Value $errorMessage -Encoding ASCII
    Write-Host "Error message ($ErrorMessageNumber) extracted to: $errorFilePath"
    
    # Write the remaining messages to another file
    $remainingContent = $remainingMessages -join ""
    Set-Content -Path $remainingFilePath -Value $remainingContent -Encoding ASCII
    Write-Host "Remaining messages ($($ErrorMessageNumber+1)-$($messages.Count)) extracted to: $remainingFilePath"
    
    # Output statistics
    Write-Host "Original file: $($messages.Count) messages"
    Write-Host "Error file: 1 message"
    Write-Host "Remaining file: $($remainingMessages.Count) messages"
} else {
    # Create a clean file with the error message removed
    $cleanMessages = @()
    for ($i = 0; $i -lt $messages.Count; $i++) {
        if ($i -ne ($ErrorMessageNumber - 1)) {
            $cleanMessages += $messages[$i]
        }
    }
    
    $cleanContent = $cleanMessages -join ""
    Set-Content -Path $cleanFilePath -Value $cleanContent -Encoding ASCII
    
    # Write the error message to its own file
    Set-Content -Path $errorFilePath -Value $errorMessage -Encoding ASCII
    
    Write-Host "Original file: $($messages.Count) messages"
    Write-Host "Error message ($ErrorMessageNumber) extracted to: $errorFilePath"
    Write-Host "Clean file (error removed): $($cleanMessages.Count) messages, saved to: $cleanFilePath"
}