Describe 'Public-tree privacy scanner fail-closed fixtures' {
	BeforeAll {
		$RepositoryRoot = Split-Path -Parent $PSScriptRoot
		$Scanner = Join-Path $RepositoryRoot 'tools\scan-public-tree.mjs'
		$Node = (Get-Command node -ErrorAction Stop).Source

		function New-PrivacyScannerFixture {
			param([Parameter(Mandatory = $true)] [string] $Path)
			$manifestRoot = Join-Path $Path 'manifests'
			New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
			foreach ($name in @('suite.json', 'media-provenance.json', 'wa-code-review.json')) {
				Copy-Item -LiteralPath (Join-Path $RepositoryRoot "manifests\$name") -Destination (Join-Path $manifestRoot $name)
			}
			return $Path
		}

		function Invoke-PrivacyScannerFixture {
			param([Parameter(Mandatory = $true)] [string] $Path)

			$previousPreference = $ErrorActionPreference
			try {
				# Windows PowerShell 5.1 wraps native stderr as non-terminating
				# ErrorRecord objects. Capture those records without allowing an
				# expected scanner rejection to abort the Pester assertion itself.
				$ErrorActionPreference = 'Continue'
				$output = @(& $Node $Scanner --root $Path 2>&1)
				$exitCode = $LASTEXITCODE
			}
			finally {
				$ErrorActionPreference = $previousPreference
			}

			return [pscustomobject]@{
				ExitCode = $exitCode
				Output = ($output | ForEach-Object { $_.ToString() }) -join "`n"
			}
		}
	}

	It 'rejects a case-insensitive SavedVariables path' {
		$root = New-PrivacyScannerFixture -Path (Join-Path $TestDrive 'saved-variables-fixture')
		$privateRoot = Join-Path $root 'SaVeDvArIaBlEs'
		New-Item -ItemType Directory -Path $privateRoot | Out-Null
		'synthetic private state' | Set-Content -LiteralPath (Join-Path $privateRoot 'state.txt') -Encoding UTF8

		$result = Invoke-PrivacyScannerFixture -Path $root
		$result.ExitCode | Should -Not -Be 0
		$result.Output | Should -Match 'Denied client/private path segment'
	}

	It 'rejects a concrete absolute Windows path in text' {
		$root = New-PrivacyScannerFixture -Path (Join-Path $TestDrive 'absolute-path-fixture')
		$docs = Join-Path $root 'docs'
		New-Item -ItemType Directory -Path $docs | Out-Null
		$syntheticPath = 'Q:' + '\Private\Synthetic\file.txt'
		("path = `"$syntheticPath`"") | Set-Content -LiteralPath (Join-Path $docs 'unsafe.md') -Encoding UTF8

		$result = Invoke-PrivacyScannerFixture -Path $root
		$result.ExitCode | Should -Not -Be 0
		$result.Output | Should -Match 'Absolute local machine path found'
	}

	It 'rejects LoginUI filenames even when their contents look harmless' -TestCases @(
		@{ FileName = 'loginui.lua' }
		@{ FileName = 'LoGiNuI.lua' }
		@{ FileName = 'old-LoginUI-copy.txt' }
	) {
		param($FileName)
		$root = New-PrivacyScannerFixture -Path (Join-Path $TestDrive ('login-fixture-' + $FileName))
		'-- synthetic fixture without any credentials' | Set-Content -LiteralPath (Join-Path $root $FileName) -Encoding UTF8
		$result = Invoke-PrivacyScannerFixture -Path $root
		$result.ExitCode | Should -Not -Be 0
		$result.Output | Should -Match 'Sensitive login UI file is never public'
	}
}
