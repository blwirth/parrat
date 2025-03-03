# concatenate-hl7.ps1
# Script to concatenate multiple HL7 files into a single file
# Usage: 
#   .\concatenate-hl7.ps1 -FolderPath "C:\path\to\folder" -OutputFile "combined.hl7" -Mode "All"
#   .\concatenate-hl7.ps1 -FilePaths @("file1.hl7", "file2.hl7") -OutputFile "combined.hl7"
#   .\concatenate-hl7.ps1 (will prompt for options)

param(
    [Parameter(Mandatory=$false)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false)]
    [string[]]$FilePaths,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("All", "Select", "Pattern")]
    [string]$Mode = "All",
    
    [Parameter(Mandatory=$false)]
    [string]$FilePattern = "*.hl7",
    
    [Parameter(Mandatory=$false)]
    [bool]$AppendMessageCount = $true
)

# Function to get a valid folder path
function Get-ValidFolderPath {
    $folderPathPrompt = Read-Host "Enter the folder path containing HL7 files (e.g., 'C:\path\to\folder') or type 'browse' to select a folder"
    
    if ($folderPathPrompt -eq "browse") {
        try {
            # Try to use the more reliable Out-GridView method first
            $folderBrowser = New-Object -ComObject Shell.Application
            $selectedFolder = $folderBrowser.BrowseForFolder(0, "Select a folder containing HL7 files", 0, 0)
            
            if ($null -ne $selectedFolder) {
                return $selectedFolder.Self.Path
            } else {
                Write-Host "No folder selected. Please try again."
                return Get-ValidFolderPath
            }
        } catch {
            # Fallback to PowerShell script method if COM object fails
            Write-Host "Using alternative folder browser method..."
            
            # Create a temporary script to launch a folder dialog
            $tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
            
            @'
Add-Type -AssemblyName System.Windows.Forms
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select a folder containing HL7 files"
$folderBrowser.ShowNewFolderButton = $true

if ($folderBrowser.ShowDialog() -eq "OK") {
    $folderBrowser.SelectedPath | Out-File -FilePath "$env:TEMP\selected_folder.txt" -Encoding utf8
}
'@ | Out-File -FilePath $tempFile -Encoding utf8
            
            # Run the script in a new PowerShell process
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`"" -Wait
            
            # Check if a folder was selected
            $selectedFolderPath = "$env:TEMP\selected_folder.txt"
            if (Test-Path $selectedFolderPath) {
                $selectedFolder = Get-Content $selectedFolderPath -Raw
                Remove-Item $selectedFolderPath -Force
                Remove-Item $tempFile -Force
                
                if ([string]::IsNullOrWhiteSpace($selectedFolder)) {
                    Write-Host "No folder selected. Please try again."
                    return Get-ValidFolderPath
                }
                
                return $selectedFolder.Trim()
            } else {
                Remove-Item $tempFile -Force
                Write-Host "No folder selected. Please try again."
                return Get-ValidFolderPath
            }
        }
    } else {
        # Remove any quotes that might have been added
        $folderPathPrompt = $folderPathPrompt -replace "^[`"']|[`"']$", ""
        
        # Check if path is valid
        if (Test-Path $folderPathPrompt -PathType Container) {
            return $folderPathPrompt
        } else {
            # Try to fix common path issues
            if ($folderPathPrompt -match "^C:(?!\\)") {
                $correctedPath = $folderPathPrompt -replace "^C:", "C:\"
                if (Test-Path $correctedPath -PathType Container) {
                    Write-Host "Corrected path to: $correctedPath"
                    return $correctedPath
                }
            }
            
            Write-Host "The specified folder does not exist: $folderPathPrompt"
            Write-Host "Please check the path and try again."
            return Get-ValidFolderPath
        }
    }
}

# Function to get a valid output file path
function Get-ValidOutputFilePath {
    param(
        [bool]$AskForAppendCount = $true
    )
    
    $outputFilePrompt = Read-Host "Enter the output file path (e.g., 'C:\path\to\combined.hl7') or type 'browse' to select a location"
    
    if ($AskForAppendCount) {
        $appendCountPrompt = Read-Host "Would you like to append the message count to the filename? (Y/N, default: Y)"
        $script:AppendMessageCount = ($appendCountPrompt -eq "" -or $appendCountPrompt.ToLower() -eq "y")
    }
    
    if ($outputFilePrompt -eq "browse") {
        try {
            # Try to use the more reliable Out-GridView method first
            $fileBrowser = New-Object -ComObject Microsoft.Office.Interop.Excel.Application
            $fileBrowser.Visible = $false
            $fileBrowser.DisplayAlerts = $false
            
            $fileDialog = $fileBrowser.FileDialog([Microsoft.Office.Interop.Excel.XlFileDialogType]::xlFileDialogSaveAs)
            $fileDialog.Title = "Save Combined HL7 File As"
            
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
                return Get-ValidOutputFilePath -AskForAppendCount $false
            }
        } catch {
            # Fallback to PowerShell script method if COM object fails
            Write-Host "Using alternative file browser method..."
            
            # Create a temporary script to launch a file dialog
            $tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
            
            @'
Add-Type -AssemblyName System.Windows.Forms
$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
$saveFileDialog.Filter = "HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*"
$saveFileDialog.Title = "Save Combined HL7 File As"
$saveFileDialog.DefaultExt = "hl7"
$saveFileDialog.AddExtension = $true

if ($saveFileDialog.ShowDialog() -eq "OK") {
    $saveFileDialog.FileName | Out-File -FilePath "$env:TEMP\selected_output_file.txt" -Encoding utf8
}
'@ | Out-File -FilePath $tempFile -Encoding utf8
            
            # Run the script in a new PowerShell process
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`"" -Wait
            
            # Check if a file was selected
            $selectedFilePath = "$env:TEMP\selected_output_file.txt"
            if (Test-Path $selectedFilePath) {
                $selectedFile = Get-Content $selectedFilePath -Raw
                Remove-Item $selectedFilePath -Force
                Remove-Item $tempFile -Force
                
                if ([string]::IsNullOrWhiteSpace($selectedFile)) {
                    Write-Host "No file selected. Please try again."
                    return Get-ValidOutputFilePath -AskForAppendCount $false
                }
                
                return $selectedFile.Trim()
            } else {
                Remove-Item $tempFile -Force
                Write-Host "No file selected. Please try again."
                return Get-ValidOutputFilePath -AskForAppendCount $false
            }
        }
    } else {
        # Remove any quotes that might have been added
        $outputFilePrompt = $outputFilePrompt -replace "^[`"']|[`"']$", ""
        
        # Check if the directory exists
        $directory = Split-Path -Parent $outputFilePrompt
        if (-not [string]::IsNullOrEmpty($directory) -and -not (Test-Path $directory -PathType Container)) {
            Write-Host "The directory does not exist: $directory"
            Write-Host "Please specify a valid directory."
            return Get-ValidOutputFilePath -AskForAppendCount $false
        }
        
        # If no directory was specified, use the current directory
        if ([string]::IsNullOrEmpty($directory)) {
            $outputFilePrompt = Join-Path (Get-Location) $outputFilePrompt
        }
        
        # Ensure the file has an .hl7 extension
        if (-not $outputFilePrompt.EndsWith(".hl7")) {
            $outputFilePrompt = $outputFilePrompt + ".hl7"
        }
        
        return $outputFilePrompt
    }
}

# Function to select files from a folder using Out-GridView
function Select-FilesFromFolder {
    param(
        [string]$FolderPath,
        [string]$Pattern = "*.hl7"
    )
    
    $files = Get-ChildItem -Path $FolderPath -Filter $Pattern | Sort-Object LastWriteTime
    
    if ($files.Count -eq 0) {
        Write-Host "No HL7 files found in the specified folder."
        return @()
    }
    
    try {
        # Try to use Out-GridView for selection
        $selectedFiles = $files | Out-GridView -Title "Select HL7 Files to Concatenate" -OutputMode Multiple
        return $selectedFiles.FullName
    } catch {
        # Fallback to console selection if Out-GridView is not available
        Write-Host "File selection dialog not available. Using console selection instead."
        Write-Host "Available files:"
        
        for ($i = 0; $i -lt $files.Count; $i++) {
            Write-Host "[$i] $($files[$i].Name) (Last Modified: $($files[$i].LastWriteTime))"
        }
        
        $selections = Read-Host "Enter the numbers of the files to select (comma-separated, or 'all' for all files)"
        
        if ($selections.ToLower() -eq "all") {
            return $files.FullName
        }
        
        $selectedIndices = $selections -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' -and [int]$_ -lt $files.Count }
        return $selectedIndices | ForEach-Object { $files[[int]$_].FullName }
    }
}

# Function to get files based on the selected mode
function Get-FilesToConcatenate {
    param(
        [string]$FolderPath,
        [string]$Mode,
        [string]$Pattern
    )
    
    switch ($Mode) {
        "All" {
            $files = Get-ChildItem -Path $FolderPath -Filter $Pattern | Sort-Object LastWriteTime
            return $files.FullName
        }
        "Select" {
            return Select-FilesFromFolder -FolderPath $FolderPath -Pattern $Pattern
        }
        "Pattern" {
            $customPattern = Read-Host "Enter a file pattern (e.g., '*part*.hl7')"
            $files = Get-ChildItem -Path $FolderPath -Filter $customPattern | Sort-Object LastWriteTime
            return $files.FullName
        }
    }
}

# If parameters are not provided, prompt the user
if (-not $FolderPath -and $FilePaths.Count -eq 0) {
    $selectionMethod = Read-Host "Do you want to select files from a folder or specify individual files? (F for folder, I for individual files)"
    
    if ($selectionMethod.ToLower() -eq "f") {
        $FolderPath = Get-ValidFolderPath
        
        $modeOptions = @{
            "1" = "All HL7 files in the folder";
            "2" = "Select specific files from the folder";
            "3" = "Files matching a pattern"
        }
        
        Write-Host "Select mode:"
        foreach ($key in $modeOptions.Keys | Sort-Object) {
            Write-Host "$key. $($modeOptions[$key])"
        }
        
        $modeSelection = Read-Host "Enter your choice (1-3)"
        
        switch ($modeSelection) {
            "1" { $Mode = "All" }
            "2" { $Mode = "Select" }
            "3" { $Mode = "Pattern" }
            default { $Mode = "All" }
        }
    } else {
        $FilePaths = @()
        $addMore = $true
        
        while ($addMore) {
            $filePath = Read-Host "Enter the path to an HL7 file (or type 'done' to finish)"
            
            if ($filePath.ToLower() -eq "done") {
                $addMore = $false
            } else {
                if (Test-Path $filePath -PathType Leaf) {
                    $FilePaths += $filePath
                } else {
                    Write-Host "File not found: $filePath"
                }
            }
        }
    }
}

if (-not $OutputFile) {
    $OutputFile = Get-ValidOutputFilePath
} else {
    # If OutputFile was provided as a parameter, ask about appending message count
    $appendCountPrompt = Read-Host "Would you like to append the message count to the filename? (Y/N, default: Y)"
    $AppendMessageCount = ($appendCountPrompt -eq "" -or $appendCountPrompt.ToLower() -eq "y")
}

# Get the list of files to concatenate
$filesToConcatenate = @()

if ($FolderPath) {
    if (-not (Test-Path $FolderPath -PathType Container)) {
        Write-Error "The specified folder does not exist: $FolderPath"
        exit 1
    }
    
    $filesToConcatenate = Get-FilesToConcatenate -FolderPath $FolderPath -Mode $Mode -Pattern $FilePattern
} elseif ($FilePaths.Count -gt 0) {
    # Verify each file exists
    foreach ($file in $FilePaths) {
        if (Test-Path $file -PathType Leaf) {
            $filesToConcatenate += $file
        } else {
            Write-Warning "File not found and will be skipped: $file"
        }
    }
}

# Check if we have any files to concatenate
if ($filesToConcatenate.Count -eq 0) {
    Write-Error "No valid files found to concatenate."
    exit 1
}

# Sort files by last modified date
$sortedFiles = Get-Item $filesToConcatenate | Sort-Object LastWriteTime | Select-Object -ExpandProperty FullName

Write-Host "Will concatenate $($sortedFiles.Count) files in the following order:"
for ($i = 0; $i -lt $sortedFiles.Count; $i++) {
    $fileInfo = Get-Item $sortedFiles[$i]
    Write-Host "$($i+1). $($fileInfo.Name) (Last Modified: $($fileInfo.LastWriteTime))"
}

# Concatenate the files
$combinedContent = ""
$totalMessages = 0

foreach ($file in $sortedFiles) {
    $content = Get-Content -Path $file -Raw
    
    # Count the number of MSH segments (approximate message count)
    $messageCount = ([regex]::Matches($content, "(?m)^MSH\|")).Count
    $totalMessages += $messageCount
    
    # Don't add extra newlines - just append the content directly
    $combinedContent += $content
    Write-Host "Added $messageCount messages from $file"
}

# Modify the output filename if needed
if ($AppendMessageCount) {
    $outputDirectory = Split-Path -Parent $OutputFile
    $outputFilename = Split-Path -Leaf $OutputFile
    $outputBasename = [System.IO.Path]::GetFileNameWithoutExtension($outputFilename)
    $outputExtension = [System.IO.Path]::GetExtension($outputFilename)
    
    # Create the new filename with message count
    $newOutputFilename = "${outputBasename}_${totalMessages}msgs${outputExtension}"
    
    # Handle case where output directory might be empty (current directory)
    if ([string]::IsNullOrEmpty($outputDirectory)) {
        $OutputFile = $newOutputFilename
    } else {
        $OutputFile = Join-Path $outputDirectory $newOutputFilename
    }
}

# Write the combined content to the output file
Set-Content -Path $OutputFile -Value $combinedContent -Encoding ASCII -NoNewline

Write-Host "`nSuccessfully concatenated $($sortedFiles.Count) files with approximately $totalMessages total messages."
Write-Host "Output file: $OutputFile" 