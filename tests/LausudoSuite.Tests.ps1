BeforeAll {
	$RepositoryRoot = Split-Path -Parent $PSScriptRoot
	$ModulePath = Join-Path $RepositoryRoot 'tools\LausudoSuite\LausudoSuite.psd1'
	Import-Module -Name $ModulePath -Force

	function New-LausudoTestClient {
		param(
			[Parameter(Mandatory = $true)] [string] $Path,
			[string] $Version = '3.3.5.12340',
			[ValidateSet('x86', 'x64')] [string] $Platform = 'x86'
		)

		New-Item -ItemType Directory -Path $Path -Force | Out-Null
		New-Item -ItemType Directory -Path (Join-Path $Path 'Data') -Force | Out-Null
		$sourcePath = Join-Path $Path 'Fixture.cs'
		$source = @"
using System.Reflection;
[assembly: AssemblyFileVersion("$Version")]
[assembly: AssemblyVersion("$Version")]
public static class Program { public static void Main() {} }
"@
		$source | Set-Content -LiteralPath $sourcePath -Encoding UTF8
		$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
		if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The test fixture compiler is unavailable.' }
		& $compiler /nologo /target:winexe "/platform:$Platform" "/out:$Path\Wow.exe" $sourcePath
		if ($LASTEXITCODE -ne 0) { throw 'Unable to compile the synthetic Wow.exe fixture.' }
		Remove-Item -LiteralPath $sourcePath -Force
		return $Path
	}
}

Describe 'LausudoSuite manifest and path safety' {
	It 'loads the build-12340 x86 suite manifest' {
		$manifest = Get-LausudoSuiteManifest
		$manifest.schemaVersion | Should -Be 1
		$manifest.target.wowBuild | Should -Be 12340
		$manifest.target.architecture | Should -Be 'x86'
		@($manifest.components | Where-Object distribution -eq 'bundled').Count | Should -BeGreaterThan 0
	}

	It 'pins the third-party addon and DXVK sources' {
		$manifest = Get-LausudoSuiteManifest
		($manifest.components | Where-Object id -eq 'tidyplates').source.commit | Should -Be 'a668fc23d329356ad6e808fc084fd0f4094b43e3'
		($manifest.components | Where-Object id -eq 'threatplates').source.commit | Should -Be 'a668fc23d329356ad6e808fc084fd0f4094b43e3'
		($manifest.components | Where-Object id -eq 'weakauras').source.commit | Should -Be '4bf5c1e9638bf822ca23339f5e4f4bcdbb1e39c4'
		($manifest.components | Where-Object id -eq 'dxvk').source.sha256 | Should -Match '^[0-9a-f]{64}$'
	}

	It 'accepts children and rejects sibling-prefix paths' {
		$root = Join-Path $TestDrive 'root'
		$child = Join-Path $root 'child\file.txt'
		$sibling = Join-Path $TestDrive 'root-other\file.txt'
		Test-LausudoPathContainment -Parent $root -Child $child | Should -BeTrue
		Test-LausudoPathContainment -Parent $root -Child $sibling | Should -BeFalse
		Test-LausudoPathContainment -Parent $root -Child $root | Should -BeFalse
		Test-LausudoPathContainment -Parent $root -Child $root -AllowEqual | Should -BeTrue
	}

	It 'rejects absolute and traversal archive entries' {
		Test-LausudoArchiveEntries -Entry @('dxvk/file.txt', 'folder/child/file.dll') | Should -BeTrue
		{ Test-LausudoArchiveEntries -Entry '../escape.txt' } | Should -Throw
		{ Test-LausudoArchiveEntries -Entry 'folder/../../escape.txt' } | Should -Throw
		{ Test-LausudoArchiveEntries -Entry '/absolute/file.txt' } | Should -Throw
		$driveEntry = 'Q:' + '\absolute\file.txt'
		{ Test-LausudoArchiveEntries -Entry $driveEntry } | Should -Throw
		{ Test-LausudoArchiveEntries -Entry 'folder/CON.txt' } | Should -Throw
		{ Test-LausudoArchiveEntries -Entry 'folder/trailing-dot.' } | Should -Throw
	}

	It 'creates a bundled plan containing only bounded public UI targets' {
		$client = Join-Path $TestDrive 'plan-client'
		New-Item -ItemType Directory -Path $client | Out-Null
		$plan = @(New-LausudoBundledFilePlan -WowPath $client)
		$plan.Count | Should -BeGreaterThan 20
		@($plan | Where-Object { -not (Test-LausudoPathContainment -Parent $client -Child $_.TargetPath) }).Count | Should -Be 0
		@($plan | Where-Object TargetRelative -Match '(?i)(^|\\)(WTF|Data|Account|Backups|Logs|Screenshots)(\\|$)').Count | Should -Be 0
		@($plan | Where-Object ComponentId -eq 'lausudo-style').Count | Should -BeGreaterThan 0
		@($plan | Where-Object ComponentId -eq 'lausudo-visual-core').Count | Should -BeGreaterThan 0
	}
}

Describe 'WoW executable validation' {
	It 'accepts a synthetic x86 build-12340 executable' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'valid-client')
		$result = Test-LausudoWowExecutable -WowPath $client
		$result.Architecture | Should -Be 'x86'
		$result.Build | Should -Be 12340
	}

	It 'rejects a different build' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'wrong-build') -Version '3.3.5.9999'
		{ Test-LausudoWowExecutable -WowPath $client } | Should -Throw '*build must be 12340*'
	}

	It 'rejects an x64 executable' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'wrong-architecture') -Platform x64
		{ Test-LausudoWowExecutable -WowPath $client } | Should -Throw '*must be x86*'
	}

	It 'rejects a client reached through an ancestor junction' {
		$realParent = Join-Path $TestDrive 'real-client-parent'
		$client = New-LausudoTestClient -Path (Join-Path $realParent 'client')
		$linkParent = Join-Path $TestDrive 'client-parent-link'
		New-Item -ItemType Junction -Path $linkParent -Target $realParent | Out-Null
		$linkedClient = Join-Path $linkParent 'client'

		{ Test-LausudoWowExecutable -WowPath $linkedClient } | Should -Throw '*Reparse points*'
	}
}

Describe 'HD patch metadata validation' {
	It 'checks only manifest-listed enabled and disabled files' {
		$client = Join-Path $TestDrive 'hd-client'
		$data = Join-Path $client 'Data'
		New-Item -ItemType Directory -Path (Join-Path $data 'enUS') -Force | Out-Null
		[System.IO.File]::WriteAllBytes((Join-Path $data 'patch-a.mpq'), [byte[]](1, 2, 3))
		[System.IO.File]::WriteAllBytes((Join-Path $data 'enUS\patch-enUS-b.mpq.disabled'), [byte[]](4, 5))
		[System.IO.File]::WriteAllBytes((Join-Path $data 'unlisted.mpq'), [byte[]](9))
		$hash = (Get-FileHash -LiteralPath (Join-Path $data 'patch-a.mpq') -Algorithm SHA256).Hash.ToLowerInvariant()
		$localeHash = (Get-FileHash -LiteralPath (Join-Path $data 'enUS\patch-enUS-b.mpq.disabled') -Algorithm SHA256).Hash.ToLowerInvariant()
		$manifestPath = Join-Path $TestDrive 'hd-test.json'
		@{
			schemaVersion = 1
			profile = 'test'
			locales = @('enUS')
			patches = @(
				@{ id = 'global'; label = 'Global'; pathTemplate = 'patch-a.mpq'; state = 'enabled'; bytes = 3; sha256 = $hash },
				@{ id = 'locale'; label = 'Locale'; pathTemplate = '{locale}\patch-{locale}-b.mpq'; state = 'disabled'; bytes = 2; sha256ByLocale = @{ enUS = $localeHash } }
			)
		} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

		$result = @(Get-LausudoHdState -WowPath $client -Locale enUS -FullHash -ManifestPath $manifestPath)
		$result.Count | Should -Be 2
		@($result | Where-Object { -not $_.StateMatches -or -not $_.SizeMatches }).Count | Should -Be 0
		($result | Where-Object Id -eq 'global').HashMatches | Should -BeTrue
		($result | Where-Object Id -eq 'locale').HashMatches | Should -BeTrue
		@($result.RelativePath) | Should -Not -Contain 'unlisted.mpq'
	}

	It 'rejects a manifest path that escapes Data' {
		$client = Join-Path $TestDrive 'hd-traversal-client'
		New-Item -ItemType Directory -Path (Join-Path $client 'Data') -Force | Out-Null
		$manifestPath = Join-Path $TestDrive 'hd-traversal.json'
		@{
			schemaVersion = 1
			profile = 'test'
			locales = @('enUS')
			patches = @(@{ id = 'escape'; label = 'Escape'; pathTemplate = '..\outside.mpq'; state = 'enabled'; bytes = 1 })
		} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
		{ Get-LausudoHdState -WowPath $client -Locale enUS -ManifestPath $manifestPath } | Should -Throw '*escapes Data*'
	}
}

Describe 'Receipt-owned installation lifecycle' {
	BeforeEach {
		$script:PriorStateOverride = [Environment]::GetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT')
		$script:StateRoot = Join-Path $TestDrive ('suite-state-' + [guid]::NewGuid().ToString('N'))
		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $script:StateRoot)
	}

	AfterEach {
		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $script:PriorStateOverride)
	}

	It 'audits without creating installer state' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'audit-client')
		$result = Invoke-LausudoSuite -WowPath $client -Action Audit -Components UI -Locale enUS
		$result.Action | Should -Be 'Audit'
		Test-Path -LiteralPath $script:StateRoot | Should -BeFalse
	}

	It 'installs UI files and restores the exact pre-existing file on uninstall' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'lifecycle-client')
		$existing = Join-Path $client 'Interface\AddOns\CrispFCT\CrispFCT.toc'
		New-Item -ItemType Directory -Path (Split-Path -Parent $existing) -Force | Out-Null
		$original = 'synthetic pre-installation file'
		$original | Set-Content -LiteralPath $existing -Encoding UTF8
		$privateMarker = Join-Path $client 'WTF\synthetic-marker.txt'
		New-Item -ItemType Directory -Path (Split-Path -Parent $privateMarker) -Force | Out-Null
		('synthetic-' + 'private-marker') | Set-Content -LiteralPath $privateMarker -Encoding UTF8
		$markerHash = (Get-FileHash -LiteralPath $privateMarker -Algorithm SHA256).Hash

		$install = Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false
		$install.Changed | Should -BeTrue
		(Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $RepositoryRoot 'packages\addons\CrispFCT\CrispFCT.toc') -Algorithm SHA256).Hash
		$receipts = @(Get-ChildItem -LiteralPath (Join-Path $script:StateRoot 'Receipts') -Filter current.json -File -Recurse)
		$receipts.Count | Should -Be 1

		$uninstall = Invoke-LausudoSuite -WowPath $client -Action Uninstall -Components UI -Locale enUS -Confirm:$false
		$uninstall.Conflicts.Count | Should -Be 0
		(Get-Content -LiteralPath $existing -Raw).Trim() | Should -Be $original
		Test-Path -LiteralPath (Join-Path $client 'Interface\AddOns\LausudoStyle\LausudoStyle.toc') | Should -BeFalse
		(Get-FileHash -LiteralPath $privateMarker -Algorithm SHA256).Hash | Should -Be $markerHash
		@(Get-ChildItem -LiteralPath (Join-Path $script:StateRoot 'Receipts') -Filter current.json -File -Recurse).Count | Should -Be 0
	}

	It 'preserves a file changed after installation and retains only its active receipt entry' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'conflict-client')
		Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false | Out-Null
		$changedFile = Join-Path $client 'Interface\AddOns\LausudoStyle\Core.lua'
		$changedText = '-- synthetic user change after install'
		$changedText | Set-Content -LiteralPath $changedFile -Encoding UTF8

		$result = Invoke-LausudoSuite -WowPath $client -Action Uninstall -Components UI -Locale enUS -Confirm:$false
		$result.Conflicts.Count | Should -Be 1
		(Get-Content -LiteralPath $changedFile -Raw).Trim() | Should -Be $changedText
		$currentReceipt = @(Get-ChildItem -LiteralPath (Join-Path $script:StateRoot 'Receipts') -Filter current.json -File -Recurse)
		$currentReceipt.Count | Should -Be 1
		$receipt = Get-Content -LiteralPath $currentReceipt[0].FullName -Raw | ConvertFrom-Json
		@($receipt.files).Count | Should -Be 1
		$receipt.files[0].targetRelative | Should -Be 'Interface\AddOns\LausudoStyle\Core.lua'
	}

	It 'does not download or write installer state for an opt-in runtime WhatIf preview' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'whatif-client')
		$result = Invoke-LausudoSuite -WowPath $client -Action Install -Components GraphicsRuntime -Locale enUS -Offline -WhatIf
		$result.Changed | Should -BeFalse
		Test-Path -LiteralPath (Join-Path $client 'd3d9.dll') | Should -BeFalse
		Test-Path -LiteralPath $script:StateRoot | Should -BeFalse
	}

	It 'fails closed for the permission-gated ReShade preset' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'reshade-client')
		{ Invoke-LausudoSuite -WowPath $client -Action Install -Components ReShadePreset -Locale enUS -Confirm:$false } | Should -Throw '*unavailable*'
		Test-Path -LiteralPath $script:StateRoot | Should -BeFalse
	}

	It 'rejects installer state inside or above the target client' {
		$client = New-LausudoTestClient -Path (Join-Path $TestDrive 'state-isolation-client')
		$inside = Join-Path $client '.installer-state'
		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $inside)
		{ Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false } | Should -Throw '*isolated*'
		Test-Path -LiteralPath $inside | Should -BeFalse

		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $TestDrive)
		{ Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false } | Should -Throw '*isolated*'

		$insideRepository = Join-Path $RepositoryRoot '.private-staging\synthetic-state'
		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $insideRepository)
		{ Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false } | Should -Throw '*public suite tree*'
		Test-Path -LiteralPath $insideRepository | Should -BeFalse

		$aboveRepository = Split-Path -Parent $RepositoryRoot
		[Environment]::SetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT', $aboveRepository)
		{ Invoke-LausudoSuite -WowPath $client -Action Install -Components UI -Locale enUS -Confirm:$false } | Should -Throw '*public suite tree*'
	}
}
