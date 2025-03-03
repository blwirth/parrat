param(
    [string]$TargetLocation = $(Read-Host "Enter the target folder location (default: current directory)")
)

# Default to current directory if no location is provided
if (-not $TargetLocation) {
    $TargetLocation = (Get-Location).Path
}

# Check if the target directory exists, create it if it doesn't
if (-not (Test-Path -Path $TargetLocation)) {
    try {
        New-Item -ItemType Directory -Path $TargetLocation -ErrorAction Stop
        Write-Host "Created directory: $TargetLocation"
    } catch {
        Write-Host "Error: Failed to create directory. $_" -ForegroundColor Red
        exit
    }
}

# Get naming convention option from the user
Write-Host "Choose the folder naming convention:"
Write-Host "1. YYYY_MM_Mon without a parent year folder (e.g., 2024_01_Jan)"
Write-Host "2. YYYY_MM_Mon with a parent year folder (e.g., 2024\2024_01_Jan)"
Write-Host "3. MM_Mon without a parent year folder (e.g., 01_Jan)"
Write-Host "4. MM_Mon with a parent year folder (e.g., 2024\01_Jan)"
$option = Read-Host "Enter the number corresponding to your choice (1, 2, 3, or 4)"

# Prompt for the year if needed
$Year = $null
if ($option -eq "1" -or $option -eq "2" -or $option -eq "4") {
    $Year = Read-Host "Enter the year (default: current year)"
    if (-not $Year) {
        $Year = (Get-Date).Year
    }
}

# If option is 3, ask if user wants a parent year folder
$IncludeParentYear = $false
if ($option -eq "3") {
    $IncludeParentYear = Read-Host "Do you want to place these in a parent year folder? (Y/N)"
    if ($IncludeParentYear -eq "Y" -or $IncludeParentYear -eq "y") {
        $Year = Read-Host "Enter the parent year folder name (default: current year)"
        if (-not $Year) {
            $Year = (Get-Date).Year
        }
        $IncludeParentYear = $true
    }
}

# Initialize the months array
$months = @("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

# Create folders based on selected option
for ($i = 0; $i -lt 12; $i++) {
    $folderName = ""
    $folderPath = ""

    switch ($option) {
        "1" {
            # YYYY_MM_Mon without a parent year folder
            $folderName = "{0}_{1:00}_{2}" -f $Year, ($i + 1), $months[$i]
            $folderPath = Join-Path $TargetLocation $folderName
        }
        "2" {
            # YYYY_MM_Mon with a parent year folder
            $parentFolder = Join-Path $TargetLocation $Year
            if (-not (Test-Path -Path $parentFolder)) {
                New-Item -ItemType Directory -Path $parentFolder -ErrorAction Stop
                Write-Host "Created parent year folder: $parentFolder"
            }
            $folderName = "{0}_{1:00}_{2}" -f $Year, ($i + 1), $months[$i]
            $folderPath = Join-Path $parentFolder $folderName
        }
        "3" {
            # MM_Mon without a parent year folder
            $folderName = "{0:00}_{1}" -f ($i + 1), $months[$i]
            if ($IncludeParentYear) {
                $parentFolder = Join-Path $TargetLocation $Year
                if (-not (Test-Path -Path $parentFolder)) {
                    New-Item -ItemType Directory -Path $parentFolder -ErrorAction Stop
                    Write-Host "Created parent year folder: $parentFolder"
                }
                $folderPath = Join-Path $parentFolder $folderName
            } else {
                $folderPath = Join-Path $TargetLocation $folderName
            }
        }
        "4" {
            # MM_Mon with parent year folder
            $parentFolder = Join-Path $TargetLocation $Year
            if (-not (Test-Path -Path $parentFolder)) {
                New-Item -ItemType Directory -Path $parentFolder -ErrorAction Stop
                Write-Host "Created parent year folder: $parentFolder"
            }
            $folderName = "{0:00}_{1}" -f ($i + 1), $months[$i]
            $folderPath = Join-Path $parentFolder $folderName
        }
        default {
            Write-Host "Invalid option selected. Please run the script again and choose 1, 2, 3, or 4." -ForegroundColor Red
            exit
        }
    }

    # Create the folder if it doesn't already exist
    if (-not (Test-Path -Path $folderPath)) {
        try {
            New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop
            Write-Host "Created folder: $folderPath"
        } catch {
            Write-Host "Error: Could not create folder $folderPath. $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Folder already exists: $folderPath" -ForegroundColor Yellow
    }
}

Write-Host "All folders created (or already existed) successfully." -ForegroundColor Green

# Ask if user wants to run again
Write-Host "`nWould you like to create folders in another location?" -ForegroundColor Cyan
$runAgain = Read-Host "Enter 'Y' to run again, or press Enter to exit"

if ($runAgain -eq 'Y' -or $runAgain -eq 'y') {
    # Get the path to the current script
    $scriptPath = $MyInvocation.MyCommand.Path
    # Run the script again
    & $scriptPath
} else {
    Write-Host "`nPress Enter to exit..." -ForegroundColor Cyan
    Read-Host
}
