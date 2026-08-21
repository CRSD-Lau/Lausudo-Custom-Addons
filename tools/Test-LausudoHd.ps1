[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string] $WowPath,

	[ValidatePattern('^[a-z]{2}[A-Z]{2}$')]
	[string] $Locale = 'enUS',

	[switch] $FullHash
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'LausudoSuite\LausudoSuite.psd1'
Import-Module -Name $module -Force

Get-LausudoHdState -WowPath $WowPath -Locale $Locale -FullHash:$FullHash
