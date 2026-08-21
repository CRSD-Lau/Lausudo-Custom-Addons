[CmdletBinding()]
param(
	[string] $OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$outputRoot = [System.IO.Path]::GetFullPath($OutputPath).TrimEnd('\', '/')
$manifestPath = Join-Path $repoRoot 'manifests\suite.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.suiteVersion
$fixedTimestamp = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$deniedSegments = @('wtf', 'data', 'account', 'accounts', 'savedvariables', 'backup', 'backups', 'cache', 'logs', 'errors', 'screenshots', 'crashes', 'dumps', 'codexbackups')
$deniedExtensions = @('.mpq', '.disabled', '.exe', '.dll', '.dmp', '.log', '.wtf', '.bak', '.old', '.tmp', '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.addon32', '.addon64')

function Test-ContainedPath {
	param([string] $Parent, [string] $Child)
	$parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
	$childPath = [System.IO.Path]::GetFullPath($Child).TrimEnd('\', '/')
	$prefix = $parentPath + [System.IO.Path]::DirectorySeparatorChar
	return $childPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePath {
	param([string] $Root, [string] $Target)
	$rootPath = [System.IO.Path]::GetFullPath($Root)
	$targetPath = [System.IO.Path]::GetFullPath($Target)
	if (-not ([string]::Equals($rootPath, $targetPath, [System.StringComparison]::OrdinalIgnoreCase) -or (Test-ContainedPath -Parent $rootPath -Child $targetPath))) {
		throw "Path escapes its expected root: $targetPath"
	}
	$current = $rootPath
	$paths = @($current)
	if (-not [string]::Equals($rootPath, $targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
		$relative = $targetPath.Substring($rootPath.TrimEnd('\', '/').Length + 1)
		foreach ($segment in @($relative -split '[\\/]')) {
			$current = Join-Path $current $segment
			$paths += $current
		}
	}
	foreach ($candidate in $paths) {
		if (-not (Test-Path -LiteralPath $candidate)) { break }
		$item = Get-Item -LiteralPath $candidate -Force
		if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
			throw "Reparse points are not permitted in release paths: $candidate"
		}
	}
}

if ([string]::Equals($repoRoot, $outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw 'The output directory must not be the repository root.'
}
$outputParent = Split-Path -Parent $outputRoot
if (-not $outputParent -or [string]::Equals($outputRoot, [System.IO.Path]::GetPathRoot($outputRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
	throw 'The output directory must not be a drive root.'
}
Assert-NoReparsePath -Root ([System.IO.Path]::GetPathRoot($repoRoot)) -Target $repoRoot
Assert-NoReparsePath -Root ([System.IO.Path]::GetPathRoot($outputRoot)) -Target $outputRoot

function New-FileMap {
	param([string] $Source, [string] $Entry)
	$fullSource = [System.IO.Path]::GetFullPath($Source)
	if (-not (Test-ContainedPath -Parent $repoRoot -Child $fullSource)) { throw "Release source escapes the repository: $Source" }
	if (-not (Test-Path -LiteralPath $fullSource -PathType Leaf)) { throw "Release source is missing: $Source" }
	Assert-NoReparsePath -Root $repoRoot -Target $fullSource
	$normalized = $Entry.Replace('\', '/').TrimStart('/')
	if (-not $normalized -or $normalized -match '(^|/)\.\.(/|$)' -or $normalized -match '^[A-Za-z]:') {
		throw "Unsafe release entry: $Entry"
	}
	foreach ($segment in @($normalized -split '/')) {
		if (-not $segment -or $segment -eq '.' -or $segment -match '[:*?"<>|]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
			throw "Unsafe Windows release entry: $Entry"
		}
		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($segment)
		if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "Reserved Windows release entry: $Entry" }
		if ($deniedSegments -contains $segment.ToLowerInvariant()) { throw "Denied client/private release entry: $Entry" }
	}
	if ($deniedExtensions -contains [System.IO.Path]::GetExtension($normalized).ToLowerInvariant()) {
		throw "Denied artifact type in release entry: $Entry"
	}
	if ((Get-Item -LiteralPath $fullSource).Length -gt 100MB) { throw "Release source exceeds 100 MiB: $Source" }
	return [pscustomobject]@{ Source = $fullSource; Entry = $normalized }
}

function Add-TreeToMap {
	param(
		[System.Collections.ArrayList] $Map,
		[string] $SourceRoot,
		[string] $EntryRoot
	)
	$root = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
	if (-not (Test-ContainedPath -Parent $repoRoot -Child $root)) { throw "Release tree escapes the repository: $SourceRoot" }
	if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Release tree is missing: $SourceRoot" }
	Assert-NoReparsePath -Root $repoRoot -Target $root
	foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object FullName)) {
		$relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
		[void]$Map.Add((New-FileMap -Source $file.FullName -Entry ($EntryRoot.TrimEnd('/', '\') + '/' + $relative)))
	}
}

function Assert-UniqueEntries {
	param([object[]] $Map)
	$seen = @{}
	foreach ($item in $Map) {
		$key = $item.Entry.ToLowerInvariant()
		if ($seen.ContainsKey($key)) { throw "Duplicate release entry: $($item.Entry)" }
		$seen[$key] = $true
	}
}

function New-DeterministicZip {
	param(
		[object[]] $Map,
		[string] $Destination
	)
	Assert-UniqueEntries -Map $Map
	Assert-NoReparsePath -Root $workRoot -Target $Destination
	Add-Type -AssemblyName System.IO.Compression
	$stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
	try {
		$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
		try {
			foreach ($item in @($Map | Sort-Object Entry)) {
				$entry = $archive.CreateEntry($item.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
				$entry.LastWriteTime = $fixedTimestamp
				$entry.ExternalAttributes = 0
				$entryStream = $entry.Open()
				$sourceStream = [System.IO.File]::OpenRead($item.Source)
				try { $sourceStream.CopyTo($entryStream) } finally { $sourceStream.Dispose(); $entryStream.Dispose() }
			}
		} finally {
			$archive.Dispose()
		}
	} finally {
		$stream.Dispose()
	}
}

function Add-CommonLegalFiles {
	param([System.Collections.ArrayList] $Map)
	foreach ($relative in @('LICENSE', 'README.md', 'SECURITY.md', 'THIRD-PARTY-NOTICES.md')) {
		[void]$Map.Add((New-FileMap -Source (Join-Path $repoRoot $relative) -Entry $relative))
	}
}

function New-SuiteMap {
	$map = New-Object System.Collections.ArrayList
	foreach ($component in @($manifest.components | Where-Object { $_.distribution -eq 'bundled' })) {
		if (-not $component.destination) { throw "Bundled component has no destination: $($component.id)" }
		Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot ([string]$component.source.path)) -EntryRoot ([string]$component.destination)
	}
	Add-CommonLegalFiles -Map $map
	Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot 'docs') -EntryRoot 'docs'
	Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot 'manifests') -EntryRoot 'manifests'
	Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot 'licenses') -EntryRoot 'licenses'
	[void]$map.Add((New-FileMap -Source (Join-Path $repoRoot 'third_party\README.md') -Entry 'third_party/README.md'))
	Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot 'third_party\licenses') -EntryRoot 'third_party/licenses'
	foreach ($relative in @(
		'tools\Install-LausudoSuite.ps1',
		'tools\Test-LausudoHd.ps1',
		'tools\LausudoSuite\LausudoSuite.psd1',
		'tools\LausudoSuite\LausudoSuite.psm1'
	)) {
		[void]$map.Add((New-FileMap -Source (Join-Path $repoRoot $relative) -Entry $relative))
	}
	return @($map)
}

function New-AddonMap {
	param([string] $ComponentId, [string[]] $ExtraFiles)
	$component = @($manifest.components | Where-Object { $_.id -eq $ComponentId })
	if ($component.Count -ne 1) { throw "Manifest component is missing or duplicated: $ComponentId" }
	$map = New-Object System.Collections.ArrayList
	Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot ([string]$component[0].source.path)) -EntryRoot ([string]$component[0].destination)
	foreach ($relative in $ExtraFiles) {
		[void]$map.Add((New-FileMap -Source (Join-Path $repoRoot $relative) -Entry $relative))
	}
	return @($map)
}

function New-PlatesMap {
	$map = New-Object System.Collections.ArrayList
	foreach ($componentId in @('tidyplates', 'threatplates')) {
		$component = @($manifest.components | Where-Object { $_.id -eq $componentId })[0]
		Add-TreeToMap -Map $map -SourceRoot (Join-Path $repoRoot ([string]$component.source.path)) -EntryRoot ([string]$component.destination)
	}
	foreach ($relative in @(
		'third_party\README.md',
		'third_party\licenses\TidyPlates-MIT.txt',
		'third_party\licenses\ThreatPlates-GPL-3.0.txt'
	)) {
		[void]$map.Add((New-FileMap -Source (Join-Path $repoRoot $relative) -Entry $relative))
	}
	return @($map)
}

$archiveSpecs = @(
	[pscustomobject]@{ Name = "Lausudo-Warmane-UI-Suite-$version.zip"; Map = @(New-SuiteMap) },
	[pscustomobject]@{ Name = 'CrispFCT-Warmane-3.3.5a-1.1.0.zip'; Map = @(New-AddonMap -ComponentId 'crisp-fct' -ExtraFiles @('LICENSE', 'licenses\OFL-PTSansNarrow.txt')) },
	[pscustomobject]@{ Name = 'Warmane-Font-Pack-1.0.0.zip'; Map = @(New-AddonMap -ComponentId 'warmane-font-pack' -ExtraFiles @('LICENSE', 'THIRD-PARTY-NOTICES.md')) },
	[pscustomobject]@{ Name = 'TidyPlates-and-ThreatPlates-Warmane-3.3.5a-6.5.0-5.7.zip'; Map = @(New-PlatesMap) }
)

$publishedManifestName = "Lausudo-Warmane-UI-Suite-$version.manifest.json"
$expectedOutputNames = @($archiveSpecs.Name) + @($publishedManifestName, 'SHA256SUMS.txt', 'SHA256SUMS.csv')
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Assert-NoReparsePath -Root ([System.IO.Path]::GetPathRoot($outputRoot)) -Target $outputRoot
$unexpectedOutput = @(Get-ChildItem -LiteralPath $outputRoot -Force | Where-Object { $_.Name -notin $expectedOutputNames })
if ($unexpectedOutput.Count -gt 0) {
	throw ("The release output directory contains unexpected stale content: {0}" -f (@($unexpectedOutput.Name | Sort-Object) -join ', '))
}
foreach ($existingOutput in @(Get-ChildItem -LiteralPath $outputRoot -Force)) {
	Assert-NoReparsePath -Root $outputRoot -Target $existingOutput.FullName
}
$workRoot = Join-Path $outputRoot ('.build-' + [guid]::NewGuid().ToString('N'))
if (-not (Test-ContainedPath -Parent $outputRoot -Child $workRoot)) { throw 'Unsafe build workspace path.' }
New-Item -ItemType Directory -Path $workRoot | Out-Null
Assert-NoReparsePath -Root $outputRoot -Target $workRoot

try {
	foreach ($spec in $archiveSpecs) {
		$first = Join-Path $workRoot ('first-' + $spec.Name)
		$second = Join-Path $workRoot ('second-' + $spec.Name)
		New-DeterministicZip -Map $spec.Map -Destination $first
		New-DeterministicZip -Map $spec.Map -Destination $second
		$firstHash = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash.ToLowerInvariant()
		$secondHash = (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash.ToLowerInvariant()
		if ($firstHash -ne $secondHash) { throw "Non-deterministic archive build: $($spec.Name)" }
		$destination = Join-Path $outputRoot $spec.Name
		Copy-Item -LiteralPath $first -Destination $destination -Force
	}

	Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $outputRoot $publishedManifestName) -Force
	$publishedFiles = @($archiveSpecs.Name) + @($publishedManifestName)
	$hashRows = foreach ($name in @($publishedFiles | Sort-Object)) {
		$hash = (Get-FileHash -LiteralPath (Join-Path $outputRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
		[pscustomobject]@{ Name = $name; Hash = $hash }
	}
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	$sumLines = @($hashRows | ForEach-Object { "$($_.Hash)  $($_.Name)" })
	[System.IO.File]::WriteAllLines((Join-Path $outputRoot 'SHA256SUMS.txt'), $sumLines, $utf8NoBom)
	$csvLines = @('"File","SHA256"') + @($hashRows | ForEach-Object { '"' + $_.Name.Replace('"', '""') + '","' + $_.Hash + '"' })
	[System.IO.File]::WriteAllLines((Join-Path $outputRoot 'SHA256SUMS.csv'), $csvLines, $utf8NoBom)
} finally {
	if ((Test-ContainedPath -Parent $outputRoot -Child $workRoot) -and (Test-Path -LiteralPath $workRoot -PathType Container)) {
		Assert-NoReparsePath -Root $outputRoot -Target $workRoot
		Remove-Item -LiteralPath $workRoot -Recurse -Force
	}
}

Get-ChildItem -LiteralPath $outputRoot -File |
	Where-Object { $_.Name -in $expectedOutputNames } |
	Sort-Object Name |
	Select-Object Name, Length, @{ Name = 'SHA256'; Expression = { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } }
