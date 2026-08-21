@{
	RootModule = 'LausudoSuite.psm1'
	ModuleVersion = '2.0.0'
	GUID = '5c7789be-1d03-4b82-b681-63ff1ab3128a'
	Author = 'Neil Mitchell'
	CompanyName = 'Lausudo'
	Copyright = 'Copyright (c) 2026 Neil Mitchell'
	Description = 'Privacy-first installer, audit, and HD validation functions for the Lausudo Warmane UI Suite.'
	PowerShellVersion = '5.1'
	FunctionsToExport = @(
		'Get-LausudoSuiteManifest',
		'Get-LausudoHdState',
		'Invoke-LausudoSuite',
		'New-LausudoBundledFilePlan',
		'Test-LausudoArchiveEntries',
		'Test-LausudoPathContainment',
		'Test-LausudoWowExecutable'
	)
	CmdletsToExport = @()
	VariablesToExport = @()
	AliasesToExport = @()
	PrivateData = @{
		PSData = @{
			Tags = @('Warmane', 'WoW', 'Installer', 'Privacy')
			ProjectUri = 'https://github.com/CRSD-Lau/Lausudo-Custom-Addons'
			LicenseUri = 'https://github.com/CRSD-Lau/Lausudo-Custom-Addons/blob/main/LICENSE'
		}
	}
}
