# Run-Tests.ps1
# Execute all Pester tests in the tests directory
#
# Usage:
#   pwsh -File tests/Run-Tests.ps1              # Run all tests
#   pwsh -File tests/Run-Tests.ps1 -Verbose     # Run with verbose output
#   pwsh -File tests/Run-Tests.ps1 -Name "hl7"  # Run tests matching "hl7"

param(
    [string]$Name = '*',
    [switch]$Verbose
)

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Filter.FullName = "*$Name*"
$config.Output.Verbosity = if ($Verbose) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled = $false

Invoke-Pester -Configuration $config
