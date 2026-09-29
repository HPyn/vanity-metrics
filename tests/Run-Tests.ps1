#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$localPester = Join-Path $PSScriptRoot '../.tools/Pester/5.7.1/Pester.psd1'
if (Test-Path $localPester) { Import-Module $localPester }
else { Import-Module Pester -MinimumVersion 5.7.1 }
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot 'Worker.Tests.ps1'
$configuration.Run.Exit = $true
$configuration.TestRegistry.Enabled = $false
$configuration.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $configuration
