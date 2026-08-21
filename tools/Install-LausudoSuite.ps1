[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
	[Parameter(Mandatory = $true)]
	[string] $WowPath,

	[ValidateSet('Audit', 'Install', 'Repair', 'Uninstall')]
	[string] $Action = 'Audit',

	[ValidateSet('UI', 'ReShadePreset', 'GraphicsRuntime')]
	[string[]] $Components = @('UI'),

	[ValidatePattern('^[a-z]{2}[A-Z]{2}$')]
	[string] $Locale = 'enUS',

	[switch] $FullHash,
	[switch] $Offline
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'LausudoSuite\LausudoSuite.psd1'
Import-Module -Name $module -Force

Invoke-LausudoSuite `
	-WowPath $WowPath `
	-Action $Action `
	-Components $Components `
	-Locale $Locale `
	-FullHash:$FullHash `
	-Offline:$Offline `
	-WhatIf:$WhatIfPreference
