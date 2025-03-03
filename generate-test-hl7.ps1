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
    $message += "MSH|^~\&|SENDING_APPLICATION|SENDING_FACILITY|RECEIVING_APPLICATION|RECEIVING_FACILITY|$(Get-Date -Format 'yyyyMMddHHmmss')||ORU^R01|$MessageNumber|P|2.5.1|||AL|NE|USA"
    
    # Add message identification based on position relative to error
    if ($IsBeforeError) {
        $message += "PID|1||12345||DOE^JOHN^||19800101|M||2106-3|123 MAIN ST^^ANYTOWN^NY^12345||^PRN^PH^^^555^5551234|||||||123456789"
        $message += "PV1|1|O|||||1234^SMITH^JANE^^^^^NPI||||||||||||12345|||||||||||||||||||||||||20230101"
        $message += "OBR|1|12345|67890|^Test Panel|||$(Get-Date -Format 'yyyyMMddHHmmss')|||||||$(Get-Date -Format 'yyyyMMddHHmmss')||1234^SMITH^JANE^^^^^NPI|||||||||F|||||||&GHK"
        $message += "NTE|1||I'm the message BEFORE the error at message #$ErrorNumber"
    } elseif ($IsAfterError) {
        $message += "PID|1||67890||SMITH^JANE^||19700202|F||2054-5|456 OAK ST^^ANYTOWN^NY^12345||^PRN^PH^^^555^5556789||||||987654321"
        $message += "PV1|1|O|||||5678^JONES^BOB^^^^^NPI||||||||||||67890|||||||||||||||||||||||||20230202"
        $message += "OBR|1|67890|12345|^Test Panel|||$(Get-Date -Format 'yyyyMMddHHmmss')|||||||$(Get-Date -Format 'yyyyMMddHHmmss')||5678^JONES^BOB^^^^^NPI|||||||||F|||||||&GHK"
        $message += "NTE|1||I'm the message AFTER the error at message #$ErrorNumber"
    } else {
        $message += "PID|1||$MessageNumber||REGULAR^PATIENT^||19900303|M||2028-9|789 ELM ST^^ANYTOWN^NY^12345||^PRN^PH^^^555^5552468||||||135792468"
        $message += "PV1|1|O|||||9012^REGULAR^DOCTOR^^^^^NPI||||||||||||$MessageNumber|||||||||||||||||||||||||20230303"
        $message += "OBR|1|$MessageNumber|54321|^Test Panel|||$(Get-Date -Format 'yyyyMMddHHmmss')|||||||$(Get-Date -Format 'yyyyMMddHHmmss')||9012^REGULAR^DOCTOR^^^^^NPI|||||||||F|||||||&GHK"
        $message += "NTE|1||Regular message #$MessageNumber"
    }
    
    # Add some OBX segments with realistic content, including some that might contain "MSH" in the text
    $obxTypes = @(
        "NM|Result^Units|100|mg/dL|70-110|N|||F",
        "ST|Comments|This is a normal result with no MSH markers",
        "TX|Notes|Patient history shows MSHAP syndrome in 2020",
        "CE|Diagnosis|R73.01^Impaired fasting glucose^ICD10",
        "DT|Collection Date|$(Get-Date -Format 'yyyyMMdd')",
        "TM|Collection Time|$(Get-Date -Format 'HHmmss')",
        "NM|Glucose|120|mg/dL|70-110|H|||F",
        "ST|Warning|MSH values may be elevated due to medication",
        "TX|Additional Notes|MSHA and MSHB antibodies were negative"
    )
    
    for ($i = 1; $i -le $obxCount; $i++) {
        $randomType = $obxTypes[(Get-Random -Minimum 0 -Maximum $obxTypes.Count)]
        $message += "OBX|$i|$randomType"
    }
    
    return $message -join "`r`n"
}

function New-ErrorMessage {
    param(
        [int]$MessageNumber
    )
    
    # Create a message with an error (missing a required field)
    $message = @()
    $message += "MSH|^~\&|SENDING_APPLICATION|SENDING_FACILITY|RECEIVING_APPLICATION|RECEIVING_FACILITY|$(Get-Date -Format 'yyyyMMddHHmmss')||ORU^R01|$MessageNumber|P|2.5.1|||AL|NE|USA"
    $message += "PID||ERROR_PATIENT||19500404|M||2106-3|321 ERROR ST^^ANYTOWN^NY^12345||^PRN^PH^^^555^5553690||||||246813579" # Error: Missing the required numeric field
    $message += "PV1|1|O|||||3456^ERROR^DOCTOR^^^^^NPI||||||||||||$MessageNumber|||||||||||||||||||||||||20230404"
    $message += "OBR|1|$MessageNumber|98765|^Test Panel|||$(Get-Date -Format 'yyyyMMddHHmmss')|||||||$(Get-Date -Format 'yyyyMMddHHmmss')||3456^ERROR^DOCTOR^^^^^NPI|||||||||F|||||||&GHK"
    $message += "NTE|1||I'm the ERROR message at message #$MessageNumber"
    
    # Add some OBX segments with realistic content, including some that might contain "MSH" in the text
    $obxCount = Get-Random -Minimum 5 -Maximum 20
    $obxTypes = @(
        "NM|Result^Units|100|mg/dL|70-110|N|||F",
        "ST|Comments|This is an ERROR message with MSH text embedded",
        "TX|Notes|Patient has MSHC disorder requiring follow-up",
        "CE|Diagnosis|R73.01^Impaired fasting glucose^ICD10",
        "DT|Collection Date|$(Get-Date -Format 'yyyyMMdd')",
        "TM|Collection Time|$(Get-Date -Format 'HHmmss')",
        "NM|Glucose|120|mg/dL|70-110|H|||F",
        "ST|Warning|MSH values are significantly elevated",
        "TX|Additional Notes|MSHA and MSHB antibodies were positive"
    )
    
    for ($i = 1; $i -le $obxCount; $i++) {
        $randomType = $obxTypes[(Get-Random -Minimum 0 -Maximum $obxTypes.Count)]
        $message += "OBX|$i|$randomType"
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