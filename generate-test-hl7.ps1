# Generate-TestHL7.ps1
# Script to generate a test HL7 file with the specified structure
# Usage: .\generate-test-hl7.ps1 -OutputFile "test.hl7" -MessageCount 100 -ErrorMessageNumbers @(51)
# Can also specify multiple error message numbers, e.g. @(51, 52, 53)
# If -MessageCount is not specified, default is set to 100
# If -ErrorMessageNumbers is not specified, no errors will be inserted
# If -OutputFile is not specified, a file will be created in the script directory

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",
    
    [Parameter(Mandatory=$false)]
    [int]$MessageCount = 100,
    
    [Parameter(Mandatory=$false)]
    [int[]]$ErrorMessageNumbers = @()
)

# If no output file is specified, create one in the script directory
if ([string]::IsNullOrEmpty($OutputFile)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $baseFileName = "test-hl7-$MessageCount-msgs"
    
    # Add error numbers to filename if specified
    if ($ErrorMessageNumbers.Count -gt 0) {
        $errorPart = "errors-at-" + ($ErrorMessageNumbers -join "-")
        $baseFileName = "$baseFileName-$errorPart"
    }
    
    # Check if file exists and create a unique name if needed
    $counter = 1
    $OutputFile = Join-Path $scriptDir "$baseFileName.hl7"
    while (Test-Path $OutputFile) {
        $OutputFile = Join-Path $scriptDir "$baseFileName-$counter.hl7"
        $counter++
    }
    
    Write-Host "No output file specified. Will create: $OutputFile"
}

function New-ValidMessage {
    param(
        [int]$MessageNumber,
        [bool]$IsBeforeError = $false,
        [bool]$IsAfterError = $false,
        [int]$ErrorNumber = 0
    )
    
    # Random number of OBX lines (between 5 and 20)
    $obxCount = Get-Random -Minimum 5 -Maximum 20
    
    $message = @()
    $message += "MSH|1|"
    
    # Add message identification based on position relative to error
    if ($IsBeforeError) {
        $message += "PID|1|I'm the message BEFORE the error at message #$ErrorNumber"
    } elseif ($IsAfterError) {
        $message += "PID|1|I'm the message AFTER the error at message #$ErrorNumber"
    } else {
        $message += "PID|1|Regular message #$MessageNumber"
    }
    
    $message += "PV1|1|"
    $message += "OBR|1|"
    
    for ($i = 1; $i -le $obxCount; $i++) {
        $message += "OBX|$i|"
    }
    
    return $message -join "`r`n"
}

function New-ErrorMessage {
    param(
        [int]$MessageNumber
    )
    
    # Create a message with an error (missing a required field)
    $message = @()
    $message += "MSH|1|"
    $message += "PID||I'm the ERROR message at message #$MessageNumber" # Error: Missing the required numeric field
    $message += "PV1|1|"
    $message += "OBR|1|"
    
    $obxCount = Get-Random -Minimum 5 -Maximum 20
    for ($i = 1; $i -le $obxCount; $i++) {
        $message += "OBX|$i|"
    }
    
    return $message -join "`r`n"
}

$allMessages = @()

for ($i = 1; $i -le $MessageCount; $i++) {
    # Check if this message is an error message
    $isError = $ErrorMessageNumbers -contains $i
    
    # Check if this message is before an error
    $isBeforeError = $ErrorMessageNumbers -contains ($i + 1)
    
    # Check if this message is after an error
    $isAfterError = $ErrorMessageNumbers -contains ($i - 1)
    
    if ($isError) {
        Write-Host "Generating error message for message #$i"
        $allMessages += New-ErrorMessage -MessageNumber $i
    } elseif ($isBeforeError) {
        $errorNumber = $i + 1
        $allMessages += New-ValidMessage -MessageNumber $i -IsBeforeError $true -ErrorNumber $errorNumber
    } elseif ($isAfterError) {
        $errorNumber = $i - 1
        $allMessages += New-ValidMessage -MessageNumber $i -IsAfterError $true -ErrorNumber $errorNumber
    } else {
        $allMessages += New-ValidMessage -MessageNumber $i
    }
}

$content = $allMessages -join "`r`n"
Set-Content -Path $OutputFile -Value $content -Encoding ASCII

Write-Host "Successfully generated test HL7 file with $MessageCount messages at: $OutputFile"
if ($ErrorMessageNumbers.Count -gt 0) {
    Write-Host "Inserted errors at message numbers: $($ErrorMessageNumbers -join ', ')"
}