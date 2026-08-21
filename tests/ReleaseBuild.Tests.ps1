Describe 'Deterministic release builder' {
	BeforeAll {
		$RepositoryRoot = Split-Path -Parent $PSScriptRoot
		$FirstOutput = Join-Path $TestDrive 'release-one'
		$SecondOutput = Join-Path $TestDrive 'release-two'
		& (Join-Path $RepositoryRoot 'tools\Build-Releases.ps1') -OutputPath $FirstOutput | Out-Null
		& (Join-Path $RepositoryRoot 'tools\Build-Releases.ps1') -OutputPath $SecondOutput | Out-Null
	}

	It 'produces the expected archives, manifest, and checksum files' {
		$files = @(Get-ChildItem -LiteralPath $FirstOutput -File)
		@($files | Where-Object Extension -eq '.zip').Count | Should -Be 4
		@($files | Where-Object Name -eq 'SHA256SUMS.txt').Count | Should -Be 1
		@($files | Where-Object Name -eq 'SHA256SUMS.csv').Count | Should -Be 1
		@($files | Where-Object Name -Match '\.manifest\.json$').Count | Should -Be 1
	}

	It 'produces identical bytes across independent builds' {
		foreach ($first in @(Get-ChildItem -LiteralPath $FirstOutput -File | Sort-Object Name)) {
			$second = Join-Path $SecondOutput $first.Name
			Test-Path -LiteralPath $second -PathType Leaf | Should -BeTrue
			(Get-FileHash -LiteralPath $first.FullName -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash
		}
	}

	It 'uses sorted safe entries and a fixed ZIP timestamp' {
		Add-Type -AssemblyName System.IO.Compression
		$suite = Get-ChildItem -LiteralPath $FirstOutput -Filter 'Lausudo-Warmane-UI-Suite-*.zip' -File | Select-Object -First 1
		$stream = [System.IO.File]::OpenRead($suite.FullName)
		$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
		try {
			$names = @($archive.Entries | ForEach-Object FullName)
			$names | Should -Be @($names | Sort-Object)
			@($names | Where-Object { $_ -match '(^|/)\.\.(/|$)' -or $_ -match '^[A-Za-z]:' }).Count | Should -Be 0
			@($names | Where-Object { $_ -match '(?i)(^|/)(WTF|Data|Account|Backups|Logs|Screenshots)(/|$)' }).Count | Should -Be 0
			@($names | Where-Object { $_ -match '(?i)\.(mpq|exe|dll|dmp|log|zip|bak|old|disabled)$' }).Count | Should -Be 0
			@($archive.Entries | Where-Object { $_.LastWriteTime.DateTime -ne [datetime]'2000-01-01T00:00:00' }).Count | Should -Be 0
		} finally {
			$archive.Dispose()
			$stream.Dispose()
		}
	}

	It 'publishes correct SHA-256 text checksums' {
		$lines = @(Get-Content -LiteralPath (Join-Path $FirstOutput 'SHA256SUMS.txt'))
		foreach ($line in $lines) {
			$match = [regex]::Match($line, '^([0-9a-f]{64})  (.+)$')
			$match.Success | Should -BeTrue
			$file = Join-Path $FirstOutput $match.Groups[2].Value
			(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $match.Groups[1].Value
		}
	}

	It 'fails closed when the output directory contains an unexpected stale artifact' {
		$staleOutput = Join-Path $TestDrive 'release-with-stale-content'
		New-Item -ItemType Directory -Path $staleOutput | Out-Null
		'synthetic stale artifact' | Set-Content -LiteralPath (Join-Path $staleOutput 'old-release.zip') -Encoding UTF8
		{ & (Join-Path $RepositoryRoot 'tools\Build-Releases.ps1') -OutputPath $staleOutput } | Should -Throw '*unexpected stale content*'
	}
}
