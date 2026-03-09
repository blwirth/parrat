# Recent Files Management for PARAT
# Stores recently opened files in user's LocalAppData folder

function Get-RecentFilesPath {
    <#
    .SYNOPSIS
    Returns the path to the recent files JSON and ensures the directory exists.
    #>
    $paratDir = Join-Path $env:LOCALAPPDATA "PARAT"
    if (-not (Test-Path $paratDir)) {
        try {
            New-Item -Path $paratDir -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-ParatLog -Level WARN -Message "Failed to create PARAT data directory: $($_.Exception.Message)" -Action "RECENT_FILES"
            return $null
        }
    }
    return Join-Path $paratDir "recent-files.json"
}

function Get-RecentFiles {
    <#
    .SYNOPSIS
    Returns an array of recent file objects. Returns empty array on error.
    #>
    $path = Get-RecentFilesPath
    if ($null -eq $path -or -not (Test-Path $path)) {
        return @()
    }

    try {
        $content = Get-Content -Path $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @()
        }
        $data = $content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data.files) {
            return @()
        }
        return @($data.files)
    }
    catch {
        Write-ParatLog -Level WARN -Message "Failed to read recent files: $($_.Exception.Message)" -Action "RECENT_FILES"
        return @()
    }
}

function Save-RecentFiles {
    <#
    .SYNOPSIS
    Saves the recent files array to JSON. Internal function.
    #>
    param(
        [array]$Files
    )

    $path = Get-RecentFilesPath
    if ($null -eq $path) {
        return
    }

    $data = @{
        version = 1
        maxItems = 10
        files = $Files
    }

    try {
        $json = $data | ConvertTo-Json -Depth 3
        Set-Content -Path $path -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-ParatLog -Level WARN -Message "Failed to save recent files: $($_.Exception.Message)" -Action "RECENT_FILES"
    }
}

function Add-RecentFile {
    <#
    .SYNOPSIS
    Adds a file to the recent files list. Removes duplicates and trims to 10 items.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [ValidateSet('xml', 'hl7')]
        [string]$FileType
    )

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return
    }

    # Normalize the path
    try {
        $normalizedPath = [System.IO.Path]::GetFullPath($FilePath)
    }
    catch {
        $normalizedPath = $FilePath
    }

    $files = @(Get-RecentFiles)

    # Remove any existing entry for this file (case-insensitive comparison)
    $files = @($files | Where-Object { $_.path -ne $normalizedPath })

    # Create new entry
    $newEntry = @{
        path = $normalizedPath
        lastOpened = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fileType = $FileType
    }

    # Add to beginning (most recent first)
    $files = @($newEntry) + $files

    # Trim to max 10 items
    if ($files.Count -gt 10) {
        $files = $files[0..9]
    }

    Save-RecentFiles -Files $files

    Write-ParatLog -Level INFO -Message "Added to recent files: $normalizedPath" -Action "RECENT_FILES"
}

function Clear-RecentFiles {
    <#
    .SYNOPSIS
    Clears all recent files from the list.
    #>
    Save-RecentFiles -Files @()
    Write-ParatLog -Level INFO -Message "Cleared recent files list" -Action "RECENT_FILES"
}

function Get-LastOpenedDirectory {
    <#
    .SYNOPSIS
    Gets the directory of the most recently opened file. Returns $null if none or directory no longer exists.
    #>
    $files = Get-RecentFiles
    if ($files.Count -eq 0) {
        return $null
    }

    $mostRecent = $files[0]
    if ($null -eq $mostRecent.path) {
        return $null
    }

    try {
        $dir = [System.IO.Path]::GetDirectoryName($mostRecent.path)
        if (-not [string]::IsNullOrEmpty($dir) -and (Test-Path $dir -PathType Container)) {
            return $dir
        }
    }
    catch {
        # Ignore path errors
        $null = $_.Exception
    }

    return $null
}
