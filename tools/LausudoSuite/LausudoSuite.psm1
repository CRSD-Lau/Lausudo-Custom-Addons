Set-StrictMode -Version 2.0

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:RepositoryRoot = Split-Path -Parent $script:ModuleRoot
$script:BlockedSegments = @(
	'wtf', 'data', 'account', 'accounts', 'backup', 'backups', 'cache', 'codexbackups',
	'crashes', 'dumps', 'errors', 'logs', 'screenshots', 'savedvariables'
)
$script:BlockedExtensions = @(
	'.7z', '.bak', '.bz2', '.disabled', '.dmp', '.dll', '.exe', '.gz', '.log', '.mpq',
	'.old', '.rar', '.tar', '.tgz', '.tmp', '.wtf', '.xz', '.zip'
)
$script:UiComponentIds = @(
	'crisp-fct', 'warmane-font-pack', 'lausudo-style', 'tidyplates',
	'threatplates', 'lausudo-visual-core'
)

function Get-LausudoSuiteManifest {
	[CmdletBinding()]
	param(
		[string] $Path = (Join-Path $script:RepositoryRoot 'manifests\suite.json')
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "Suite manifest not found: $Path"
	}
	return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-LausudoFullPath {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string] $Path
	)

	$full = [System.IO.Path]::GetFullPath($Path)
	$root = [System.IO.Path]::GetPathRoot($full)
	if ([string]::Equals($full, $root, [System.StringComparison]::OrdinalIgnoreCase)) { return $root }
	return $full.TrimEnd('\', '/')
}

function Test-LausudoPathContainment {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string] $Parent,

		[Parameter(Mandatory = $true)]
		[string] $Child,

		[switch] $AllowEqual
	)

	$parentPath = Get-LausudoFullPath -Path $Parent
	$childPath = Get-LausudoFullPath -Path $Child
	if ($AllowEqual -and [string]::Equals($parentPath, $childPath, [System.StringComparison]::OrdinalIgnoreCase)) {
		return $true
	}
	$prefix = if ($parentPath.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or $parentPath.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)) {
		$parentPath
	} else {
		$parentPath + [System.IO.Path]::DirectorySeparatorChar
	}
	return $childPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-LausudoRelativePath {
	param(
		[Parameter(Mandatory = $true)] [string] $Parent,
		[Parameter(Mandatory = $true)] [string] $Child
	)

	$parentPath = Get-LausudoFullPath -Path $Parent
	$childPath = Get-LausudoFullPath -Path $Child
	if (-not (Test-LausudoPathContainment -Parent $parentPath -Child $childPath -AllowEqual)) {
		throw "Path is outside its expected parent: $childPath"
	}
	if ([string]::Equals($parentPath, $childPath, [System.StringComparison]::OrdinalIgnoreCase)) {
		return ''
	}
	$prefixLength = $parentPath.Length
	if (-not ($parentPath.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or $parentPath.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar))) {
		$prefixLength += 1
	}
	return $childPath.Substring($prefixLength)
}

function Assert-LausudoNoReparsePoint {
	param(
		[Parameter(Mandatory = $true)] [string] $Root,
		[Parameter(Mandatory = $true)] [string] $Path
	)

	$rootPath = Get-LausudoFullPath -Path $Root
	$targetPath = Get-LausudoFullPath -Path $Path
	if (-not (Test-LausudoPathContainment -Parent $rootPath -Child $targetPath -AllowEqual)) {
		throw "Path escapes its expected root: $targetPath"
	}

	$current = $rootPath
	$relative = Get-LausudoRelativePath -Parent $rootPath -Child $targetPath
	$segments = @()
	if ($relative) { $segments = $relative -split '[\\/]' }
	$paths = @($current)
	foreach ($segment in $segments) {
		$current = Join-Path $current $segment
		$paths += $current
	}

	foreach ($candidate in $paths) {
		if (-not (Test-Path -LiteralPath $candidate)) { break }
		$item = Get-Item -LiteralPath $candidate -Force
		if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
			throw "Reparse points are not permitted in the target path: $candidate"
		}
		$resolved = Get-LausudoFullPath -Path $item.FullName
		if (-not (Test-LausudoPathContainment -Parent $rootPath -Child $resolved -AllowEqual)) {
			throw "Resolved path escapes its expected root: $candidate"
		}
	}
}

function Assert-LausudoPublicRelativePath {
	param(
		[Parameter(Mandatory = $true)] [string] $Path
	)

	if ([System.IO.Path]::IsPathRooted($Path)) {
		throw "A public package path must be relative: $Path"
	}
	$segments = @($Path -split '[\\/]')
	foreach ($segment in $segments) {
		if (-not $segment -or $segment -eq '.' -or $segment -eq '..') {
			throw "Unsafe path segment in public package path: $Path"
		}
		if ($segment -match '[:*?"<>|]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
			throw "Unsafe Windows path segment in public package path: $Path"
		}
		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($segment)
		if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
			throw "Reserved Windows path segment in public package path: $Path"
		}
		if ($script:BlockedSegments -contains $segment.ToLowerInvariant()) {
			throw "Blocked client/private directory in public package path: $Path"
		}
	}
	$extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
	if ($script:BlockedExtensions -contains $extension) {
		throw "Blocked artifact type in public package path: $Path"
	}
}

function Assert-LausudoInstallRelativePath {
	param(
		[Parameter(Mandatory = $true)] [string] $Path,
		[Parameter(Mandatory = $true)] [string] $ComponentId
	)

	if ($ComponentId -eq 'dxvk' -and [string]::Equals($Path, 'd3d9.dll', [System.StringComparison]::OrdinalIgnoreCase)) {
		return
	}
	Assert-LausudoPublicRelativePath -Path $Path
}

function Get-LausudoFileHash {
	param([Parameter(Mandatory = $true)] [string] $Path)
	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LausudoStringHash {
	param([Parameter(Mandatory = $true)] [string] $Value)
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
		return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
	} finally {
		$sha.Dispose()
	}
}

function Get-LausudoClientId {
	param([Parameter(Mandatory = $true)] [string] $WowPath)
	$canonical = (Get-LausudoFullPath -Path $WowPath).ToLowerInvariant()
	return (Get-LausudoStringHash -Value $canonical).Substring(0, 24)
}

function Get-LausudoStateRoot {
	$override = [Environment]::GetEnvironmentVariable('LAUSUDO_SUITE_STATE_ROOT')
	if ($override) { return (Get-LausudoFullPath -Path $override) }
	$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
	if (-not $localAppData) { throw 'LOCALAPPDATA is unavailable.' }
	return (Join-Path $localAppData 'LausudoWarmaneUISuite')
}

function Assert-LausudoStateRoot {
	param(
		[Parameter(Mandatory = $true)] [string] $StateRoot,
		[string] $WowPath
	)

	$full = Get-LausudoFullPath -Path $StateRoot
	$pathRoot = [System.IO.Path]::GetPathRoot($full)
	if (-not $pathRoot -or [string]::Equals($full, $pathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw 'The installer state directory cannot be a filesystem root.'
	}
	if ((Test-Path -LiteralPath $full) -and -not (Test-Path -LiteralPath $full -PathType Container)) {
		throw "The installer state path is not a directory: $full"
	}
	Assert-LausudoNoReparsePoint -Root $pathRoot -Path $full
	if ((Test-LausudoPathContainment -Parent $script:RepositoryRoot -Child $full -AllowEqual) -or
		(Test-LausudoPathContainment -Parent $full -Child $script:RepositoryRoot -AllowEqual)) {
		throw 'Installer state and downloads cannot be stored inside the public suite tree.'
	}

	if ($WowPath) {
		$wowRoot = Get-LausudoFullPath -Path $WowPath
		if ((Test-LausudoPathContainment -Parent $wowRoot -Child $full -AllowEqual) -or
			(Test-LausudoPathContainment -Parent $full -Child $wowRoot -AllowEqual)) {
			throw 'Installer state and downloads must be isolated from the WoW directory.'
		}
	}
	return $full
}

function Write-LausudoJsonAtomic {
	param(
		[Parameter(Mandatory = $true)] [object] $Value,
		[Parameter(Mandatory = $true)] [string] $Path
	)

	$fullPath = Get-LausudoFullPath -Path $Path
	$parent = Split-Path -Parent $fullPath
	$pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
	Assert-LausudoNoReparsePoint -Root $pathRoot -Path $fullPath
	if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
		New-Item -ItemType Directory -Path $parent -Force | Out-Null
	}
	Assert-LausudoNoReparsePoint -Root $pathRoot -Path $fullPath
	$temp = Join-Path $parent (([System.IO.Path]::GetFileName($fullPath)) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
	try {
		$Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
		Move-Item -LiteralPath $temp -Destination $fullPath -Force
	} finally {
		if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
	}
}

function Test-LausudoWowExecutable {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string] $WowPath
	)

	$root = Get-LausudoFullPath -Path $WowPath
	if (-not (Test-Path -LiteralPath $root -PathType Container)) {
		throw "WoW directory not found: $root"
	}
	if ([string]::Equals($root, [System.IO.Path]::GetPathRoot($root), [System.StringComparison]::OrdinalIgnoreCase)) {
		throw 'A drive root cannot be used as the WoW directory.'
	}
	$filesystemRoot = [System.IO.Path]::GetPathRoot($root)
	Assert-LausudoNoReparsePoint -Root $filesystemRoot -Path $root
	$exe = Join-Path $root 'Wow.exe'
	if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
		throw "Wow.exe not found in: $root"
	}
	Assert-LausudoNoReparsePoint -Root $root -Path $exe

	$stream = [System.IO.File]::Open($exe, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
	$reader = New-Object System.IO.BinaryReader($stream)
	try {
		if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'Wow.exe does not have an MZ header.' }
		$stream.Position = 0x3C
		$peOffset = $reader.ReadInt32()
		if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 6)) { throw 'Wow.exe has an invalid PE offset.' }
		$stream.Position = $peOffset
		if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Wow.exe does not have a valid PE signature.' }
		$machine = $reader.ReadUInt16()
		if ($machine -ne 0x014C) { throw ('Wow.exe must be x86 (PE machine 0x014c); found 0x{0:x4}.' -f $machine) }
	} finally {
		$reader.Dispose()
		$stream.Dispose()
	}

	$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
	$build = $version.FilePrivatePart
	if ($build -ne 12340) {
		throw "Wow.exe build must be 12340; found $($version.FileVersion)."
	}

	return [pscustomobject]@{
		WowPath = $root
		Executable = $exe
		Architecture = 'x86'
		Build = $build
		Version = $version.FileVersion
	}
}

function Assert-LausudoClientNotRunning {
	param([Parameter(Mandatory = $true)] [string] $WowExecutable)

	$expected = Get-LausudoFullPath -Path $WowExecutable
	$processes = @()
	try {
		$processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='Wow.exe'" -ErrorAction Stop)
		foreach ($process in $processes) {
			if (-not $process.ExecutablePath) {
				throw 'A Wow.exe process is running, but its path could not be verified. Close it before a mutating action.'
			}
			$actual = Get-LausudoFullPath -Path $process.ExecutablePath
			if ([string]::Equals($expected, $actual, [System.StringComparison]::OrdinalIgnoreCase)) {
				throw "The target client is running (PID $($process.ProcessId)). Close it before continuing."
			}
		}
		return
	} catch {
		if ($_.Exception.Message -like 'The target client is running*' -or $_.Exception.Message -like 'A Wow.exe process is running*') { throw }
	}

	foreach ($process in @(Get-Process -Name Wow -ErrorAction SilentlyContinue)) {
		try { $actual = Get-LausudoFullPath -Path $process.Path } catch {
			throw 'A Wow.exe process is running, but its path could not be verified. Close it before a mutating action.'
		}
		if ([string]::Equals($expected, $actual, [System.StringComparison]::OrdinalIgnoreCase)) {
			throw "The target client is running (PID $($process.Id)). Close it before continuing."
		}
	}
}

function Test-LausudoArchiveEntries {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string[]] $Entry
	)

	begin { $entries = @() }
	process { $entries += $Entry }
	end {
		foreach ($name in $entries) {
			if (-not $name -or $name.IndexOf([char]0) -ge 0) { throw 'Archive contains an empty or NUL path.' }
			$normalized = $name.Replace('\', '/')
			if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or $normalized -match '^//') {
				throw "Archive contains an absolute path: $name"
			}
			$segments = @($normalized -split '/')
			for ($index = 0; $index -lt $segments.Count; $index++) {
				$segment = $segments[$index]
				if (-not $segment -and $index -eq ($segments.Count - 1)) { continue }
				if (-not $segment -or $segment -eq '.' -or $segment -eq '..') { throw "Archive contains an unsafe segment: $name" }
				if ($segment -match '[:*?"<>|]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { throw "Archive contains an unsafe Windows path: $name" }
				$baseName = [System.IO.Path]::GetFileNameWithoutExtension($segment)
				if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "Archive contains a reserved Windows name: $name" }
			}
		}
		return $true
	}
}

function New-LausudoBundledFilePlan {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[object] $Manifest = (Get-LausudoSuiteManifest),
		[string[]] $ComponentIds = $script:UiComponentIds,
		[string] $RepositoryRoot = $script:RepositoryRoot
	)

	$wowRoot = Get-LausudoFullPath -Path $WowPath
	$repoRoot = Get-LausudoFullPath -Path $RepositoryRoot
	$plan = @()
	foreach ($componentId in $ComponentIds) {
		$component = @($Manifest.components | Where-Object { $_.id -eq $componentId })
		if ($component.Count -ne 1) { throw "Manifest component is missing or duplicated: $componentId" }
		$component = $component[0]
		if ($component.distribution -ne 'bundled') { throw "Component is not bundled: $componentId" }
		if (-not $component.destination) { throw "Bundled component has no destination: $componentId" }
		Assert-LausudoPublicRelativePath -Path ([string]$component.destination)

		$sourceRoot = Get-LausudoFullPath -Path (Join-Path $repoRoot ([string]$component.source.path))
		if (-not (Test-LausudoPathContainment -Parent $repoRoot -Child $sourceRoot)) {
			throw "Bundled source escapes the repository: $componentId"
		}
		if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
			throw "Bundled source is missing: $sourceRoot"
		}
		Assert-LausudoNoReparsePoint -Root $repoRoot -Path $sourceRoot

		$destinationRoot = Get-LausudoFullPath -Path (Join-Path $wowRoot ([string]$component.destination))
		if (-not (Test-LausudoPathContainment -Parent $wowRoot -Child $destinationRoot)) {
			throw "Component destination escapes the WoW directory: $componentId"
		}

		foreach ($sourceFile in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Sort-Object FullName)) {
			Assert-LausudoNoReparsePoint -Root $sourceRoot -Path $sourceFile.FullName
			$sourceRelative = Get-LausudoRelativePath -Parent $sourceRoot -Child $sourceFile.FullName
			$targetRelative = Join-Path ([string]$component.destination) $sourceRelative
			Assert-LausudoPublicRelativePath -Path $targetRelative
			$target = Get-LausudoFullPath -Path (Join-Path $wowRoot $targetRelative)
			if (-not (Test-LausudoPathContainment -Parent $wowRoot -Child $target)) {
				throw "Planned target escapes the WoW directory: $target"
			}
			$plan += [pscustomobject]@{
				ComponentId = [string]$component.id
				SourcePath = $sourceFile.FullName
				SourceHash = Get-LausudoFileHash -Path $sourceFile.FullName
				TargetPath = $target
				TargetRelative = $targetRelative.Replace('/', '\')
			}
		}
	}
	return $plan
}

function Invoke-LausudoBoundedDownload {
	param(
		[Parameter(Mandatory = $true)] [uri] $Uri,
		[Parameter(Mandatory = $true)] [string] $Destination,
		[int64] $MaximumBytes = 134217728
	)

	if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'github.com' -or
		-not $Uri.AbsolutePath.StartsWith('/doitsujin/dxvk/releases/download/', [System.StringComparison]::Ordinal)) {
		throw 'DXVK downloads must use the pinned official GitHub release URL.'
	}
	if ($Uri.UserInfo -or -not $Uri.IsDefaultPort -or $Uri.Fragment) {
		throw 'The DXVK source URL contains unsupported authority or fragment data.'
	}
	if ($MaximumBytes -lt 1) { throw 'The download size limit must be positive.' }
	if (Test-Path -LiteralPath $Destination) { throw "Download destination already exists: $Destination" }

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$request = [System.Net.HttpWebRequest]::Create($Uri)
	$request.Method = 'GET'
	$request.AllowAutoRedirect = $true
	$request.MaximumAutomaticRedirections = 5
	$request.Timeout = 60000
	$request.ReadWriteTimeout = 60000
	$request.UserAgent = 'Lausudo-Warmane-UI-Suite/2'
	$response = $null
	$output = $null
	$responseStream = $null
	try {
		$response = [System.Net.HttpWebResponse]$request.GetResponse()
		$finalUri = $response.ResponseUri
		$allowedFinalHost = $finalUri.Host -eq 'github.com' -or $finalUri.Host -eq 'release-assets.githubusercontent.com'
		if ($finalUri.Scheme -ne 'https' -or -not $allowedFinalHost -or -not $finalUri.IsDefaultPort) {
			throw 'The DXVK download redirected outside the approved GitHub release hosts.'
		}
		if ($response.ContentLength -gt $MaximumBytes) {
			throw "The DXVK archive exceeds the $MaximumBytes-byte download limit."
		}

		$responseStream = $response.GetResponseStream()
		$output = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
		$buffer = New-Object byte[] 81920
		[int64]$total = 0
		while (($read = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
			$total += $read
			if ($total -gt $MaximumBytes) {
				throw "The DXVK archive exceeded the $MaximumBytes-byte download limit while streaming."
			}
			$output.Write($buffer, 0, $read)
		}
		$output.Flush()
		return $total
	} finally {
		if ($output) { $output.Dispose() }
		if ($responseStream) { $responseStream.Dispose() }
		if ($response) { $response.Dispose() }
	}
}

function Get-LausudoDxvkPlan {
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[Parameter(Mandatory = $true)] [object] $Manifest,
		[switch] $Offline
	)

	$component = @($Manifest.components | Where-Object { $_.id -eq 'dxvk' })
	if ($component.Count -ne 1) { throw 'The DXVK component is missing or duplicated in the manifest.' }
	$component = $component[0]
	if ($component.distribution -ne 'download') { throw 'DXVK must be a pinned download component.' }

	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot) -WowPath $WowPath
	$assetName = [string]$component.source.asset
	$assetBaseName = [System.IO.Path]::GetFileNameWithoutExtension($assetName)
	if (-not $assetName -or $assetName -in @('.', '..') -or
		$assetName -ne [System.IO.Path]::GetFileName($assetName) -or
		$assetName -match '[:*?"<>|]' -or $assetName.EndsWith('.') -or $assetName.EndsWith(' ') -or
		$assetBaseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
		throw 'The DXVK manifest contains an unsafe archive asset name.'
	}
	$downloadRoot = Join-Path $stateRoot 'Downloads'
	$archive = Join-Path $downloadRoot $assetName
	Assert-LausudoNoReparsePoint -Root $stateRoot -Path $archive
	if ((Test-Path -LiteralPath $archive) -and -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
		throw "The DXVK cache path is not a regular file: $archive"
	}
	if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
		if ($Offline) { throw "Offline mode requires the verified cached archive: $archive" }
		New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
		Assert-LausudoNoReparsePoint -Root $stateRoot -Path $downloadRoot
		$partial = $archive + '.partial'
		try {
			Invoke-LausudoBoundedDownload -Uri ([uri][string]$component.source.url) -Destination $partial | Out-Null
			if ((Get-LausudoFileHash -Path $partial) -ne ([string]$component.source.sha256).ToLowerInvariant()) {
				throw 'Downloaded DXVK archive failed SHA-256 verification.'
			}
			Move-Item -LiteralPath $partial -Destination $archive -Force
		} finally {
			if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force }
		}
	}
	Assert-LausudoNoReparsePoint -Root $stateRoot -Path $archive
	if ((Get-LausudoFileHash -Path $archive) -ne ([string]$component.source.sha256).ToLowerInvariant()) {
		throw "Cached DXVK archive failed SHA-256 verification: $archive"
	}

	$tar = Get-Command tar.exe -ErrorAction Stop
	$entries = @(& $tar.Source -tf $archive)
	if ($LASTEXITCODE -ne 0) { throw 'Unable to list the DXVK archive.' }
	Test-LausudoArchiveEntries -Entry $entries | Out-Null
	$archivePath = ([string]$component.source.archivePath).Replace('\', '/')
	if ($entries -notcontains $archivePath) { throw "DXVK archive is missing its pinned member: $archivePath" }
	$verbose = @(& $tar.Source -tvf $archive $archivePath)
	if ($LASTEXITCODE -ne 0 -or $verbose.Count -ne 1 -or -not $verbose[0].TrimStart().StartsWith('-')) {
		throw 'Pinned DXVK archive member is not a regular file.'
	}

	$stagingRoot = Join-Path (Join-Path $stateRoot 'Staging') ([guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
	Assert-LausudoNoReparsePoint -Root $stateRoot -Path $stagingRoot
	try {
		& $tar.Source -xf $archive -C $stagingRoot $archivePath
		if ($LASTEXITCODE -ne 0) { throw 'Unable to extract the pinned DXVK member.' }
		$source = Get-LausudoFullPath -Path (Join-Path $stagingRoot $archivePath)
		Assert-LausudoNoReparsePoint -Root $stagingRoot -Path $source
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Extracted DXVK member is missing.' }
		$held = Join-Path $stateRoot ('Prepared\' + [guid]::NewGuid().ToString('N') + '\d3d9.dll')
		New-Item -ItemType Directory -Path (Split-Path -Parent $held) -Force | Out-Null
		Assert-LausudoNoReparsePoint -Root $stateRoot -Path $held
		Copy-Item -LiteralPath $source -Destination $held
		return [pscustomobject]@{
			ComponentId = 'dxvk'
			SourcePath = $held
			SourceHash = Get-LausudoFileHash -Path $held
			TargetPath = Join-Path (Get-LausudoFullPath -Path $WowPath) 'd3d9.dll'
			TargetRelative = 'd3d9.dll'
			PreparedRoot = Split-Path -Parent $held
		}
	} finally {
		$expectedStagingParent = Join-Path $stateRoot 'Staging'
		if ((Test-LausudoPathContainment -Parent $expectedStagingParent -Child $stagingRoot) -and (Test-Path -LiteralPath $stagingRoot)) {
			Assert-LausudoNoReparsePoint -Root $stateRoot -Path $stagingRoot
			Remove-Item -LiteralPath $stagingRoot -Recurse -Force
		}
	}
}

function Get-LausudoReceiptPath {
	param([Parameter(Mandatory = $true)] [string] $ClientId)
	if ($ClientId -notmatch '^[0-9a-f]{24}$') { throw 'The client receipt identifier is invalid.' }
	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot)
	$path = Join-Path $stateRoot ("Receipts\$ClientId\current.json")
	Assert-LausudoNoReparsePoint -Root $stateRoot -Path $path
	return $path
}

function Read-LausudoReceipt {
	param([Parameter(Mandatory = $true)] [string] $Path)
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
	return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-LausudoReceiptBackupPath {
	param(
		[Parameter(Mandatory = $true)] [object] $Receipt,
		[Parameter(Mandatory = $true)] [object] $Entry
	)

	$path = $null
	if ($Entry.PSObject.Properties.Name -contains 'backupPath' -and $Entry.backupPath) {
		$path = [string]$Entry.backupPath
	} elseif ($Receipt.backupRoot -and $Entry.backupRelative) {
		$path = Join-Path ([string]$Receipt.backupRoot) ([string]$Entry.backupRelative)
	}
	if (-not $path) { return $null }
	$full = Get-LausudoFullPath -Path $path
	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot)
	$backupBase = Join-Path $stateRoot 'Backups'
	if (-not (Test-LausudoPathContainment -Parent $backupBase -Child $full)) {
		throw 'Receipt backup path escapes the installer backup root.'
	}
	Assert-LausudoNoReparsePoint -Root $backupBase -Path $full
	return $full
}

function Invoke-LausudoInstallPlan {
	param(
		[Parameter(Mandatory = $true)] [object[]] $Plan,
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[Parameter(Mandatory = $true)] [object] $Manifest,
		[Parameter(Mandatory = $true)] [string] $Action,
		[Parameter(Mandatory = $true)] [System.Management.Automation.PSCmdlet] $Cmdlet
	)

	$clientId = Get-LausudoClientId -WowPath $WowPath
	$receiptPath = Get-LausudoReceiptPath -ClientId $clientId
	$existingReceipt = Read-LausudoReceipt -Path $receiptPath
	if ($Action -eq 'Install' -and $existingReceipt) {
		throw 'This client already has an active suite receipt. Use -Action Repair or Uninstall.'
	}

	$plannedTargets = @{}
	foreach ($item in $Plan) {
		if (-not (Test-LausudoPathContainment -Parent $WowPath -Child $item.TargetPath)) {
			throw "Install plan escapes the WoW directory: $($item.TargetPath)"
		}
		Assert-LausudoInstallRelativePath -Path $item.TargetRelative -ComponentId $item.ComponentId
		Assert-LausudoNoReparsePoint -Root $WowPath -Path $item.TargetPath
		if (Test-Path -LiteralPath $item.TargetPath -PathType Container) {
			throw "A planned file target is an existing directory: $($item.TargetPath)"
		}
		if ((Get-LausudoFileHash -Path $item.SourcePath) -ne $item.SourceHash) {
			throw "Source changed after planning: $($item.SourcePath)"
		}
		$key = ([string]$item.TargetRelative).ToLowerInvariant()
		if ($plannedTargets.ContainsKey($key)) { throw "Duplicate install target: $($item.TargetRelative)" }
		$plannedTargets[$key] = $true
	}

	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot) -WowPath $WowPath
	$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
	$backupRoot = Join-Path $stateRoot ("Backups\$clientId\$timestamp")
	Assert-LausudoNoReparsePoint -Root $stateRoot -Path $backupRoot
	$entries = @()
	$operations = @()
	$changed = $false

	try {
		foreach ($item in $Plan) {
			Assert-LausudoNoReparsePoint -Root $WowPath -Path $item.TargetPath
			$targetExists = Test-Path -LiteralPath $item.TargetPath -PathType Leaf
			$currentHash = if ($targetExists) { Get-LausudoFileHash -Path $item.TargetPath } else { $null }
			$oldEntry = $null
			if ($existingReceipt) {
				$oldEntry = @($existingReceipt.files | Where-Object { $_.targetRelative -eq $item.TargetRelative } | Select-Object -First 1)
				if ($oldEntry.Count -eq 0) { $oldEntry = $null } else { $oldEntry = $oldEntry[0] }
			}

			if ($targetExists -and $currentHash -eq $item.SourceHash) {
				if ($oldEntry) {
					$entries += $oldEntry
				} else {
					$entries += [pscustomobject]@{
						componentId = $item.ComponentId
						targetRelative = $item.TargetRelative
						installedHash = $item.SourceHash
						owned = $false
						beforeExisted = $true
						beforeHash = $currentHash
						backupPath = $null
					}
				}
				continue
			}

			if (-not $Cmdlet.ShouldProcess($item.TargetPath, "$Action suite file")) { continue }
			$changed = $true
			$rollbackPath = $null
			if ($targetExists) {
				$rollbackPath = Join-Path (Join-Path $backupRoot 'Rollback') $item.TargetRelative
				Assert-LausudoNoReparsePoint -Root $stateRoot -Path $rollbackPath
				New-Item -ItemType Directory -Path (Split-Path -Parent $rollbackPath) -Force | Out-Null
				Assert-LausudoNoReparsePoint -Root $stateRoot -Path $rollbackPath
				Copy-Item -LiteralPath $item.TargetPath -Destination $rollbackPath
				if ((Get-LausudoFileHash -Path $rollbackPath) -ne $currentHash) { throw "Backup verification failed: $rollbackPath" }
			}
			$operations += [pscustomobject]@{ TargetPath = $item.TargetPath; TargetExisted = [bool]$targetExists; RollbackPath = $rollbackPath }

			$priorOwned = $oldEntry -and $oldEntry.owned -and $targetExists -and $currentHash -eq ([string]$oldEntry.installedHash).ToLowerInvariant()
			if ($priorOwned) {
				$beforeExisted = [bool]$oldEntry.beforeExisted
				$beforeHash = $oldEntry.beforeHash
				$receiptBackupPath = Get-LausudoReceiptBackupPath -Receipt $existingReceipt -Entry $oldEntry
				if ($beforeExisted) {
					if (-not $receiptBackupPath -or -not (Test-Path -LiteralPath $receiptBackupPath -PathType Leaf)) {
						throw "Cannot preserve the original pre-installation backup for: $($item.TargetRelative)"
					}
					if ((Get-LausudoFileHash -Path $receiptBackupPath) -ne ([string]$beforeHash).ToLowerInvariant()) {
						throw "Original pre-installation backup hash mismatch for: $($item.TargetRelative)"
					}
				}
			} else {
				$beforeExisted = [bool]$targetExists
				$beforeHash = $currentHash
				$receiptBackupPath = $rollbackPath
			}

			$targetParent = Split-Path -Parent $item.TargetPath
			if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
				New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
			}
			Assert-LausudoNoReparsePoint -Root $WowPath -Path $item.TargetPath
			Copy-Item -LiteralPath $item.SourcePath -Destination $item.TargetPath -Force
			if ((Get-LausudoFileHash -Path $item.TargetPath) -ne $item.SourceHash) {
				throw "Installed file failed SHA-256 verification: $($item.TargetPath)"
			}

			$entry = [pscustomobject]@{
				componentId = $item.ComponentId
				targetRelative = $item.TargetRelative
				installedHash = $item.SourceHash
				owned = $true
				beforeExisted = $beforeExisted
				beforeHash = $beforeHash
				backupPath = $receiptBackupPath
			}
			$entries += $entry
		}

		if ($existingReceipt) {
			foreach ($oldEntry in @($existingReceipt.files)) {
				$key = ([string]$oldEntry.targetRelative).ToLowerInvariant()
				if (-not $plannedTargets.ContainsKey($key)) { $entries += $oldEntry }
			}
		}

		if ($changed) {
			$receipt = [ordered]@{
				schemaVersion = 1
				suiteVersion = [string]$Manifest.suiteVersion
				clientId = $clientId
				createdUtc = (Get-Date).ToUniversalTime().ToString('o')
				action = $Action
				backupRoot = $backupRoot
				files = @($entries)
			}
			Write-LausudoJsonAtomic -Value $receipt -Path $receiptPath
			$writtenReceipt = Read-LausudoReceipt -Path $receiptPath
			if (-not $writtenReceipt -or @($writtenReceipt.files).Count -ne $entries.Count) {
				throw 'The installation receipt failed post-write verification.'
			}
		}
	} catch {
		$installError = $_.Exception
		$rollbackErrors = @()
		for ($index = $operations.Count - 1; $index -ge 0; $index--) {
			$operation = $operations[$index]
			try {
				Assert-LausudoNoReparsePoint -Root $WowPath -Path $operation.TargetPath
				if ($operation.TargetExisted) {
					if (-not $operation.RollbackPath -or -not (Test-Path -LiteralPath $operation.RollbackPath -PathType Leaf)) {
						throw 'verified rollback snapshot is unavailable'
					}
					Copy-Item -LiteralPath $operation.RollbackPath -Destination $operation.TargetPath -Force
					if ((Get-LausudoFileHash -Path $operation.TargetPath) -ne (Get-LausudoFileHash -Path $operation.RollbackPath)) {
						throw 'hash mismatch after rollback'
					}
				} elseif (Test-Path -LiteralPath $operation.TargetPath -PathType Leaf) {
					Remove-Item -LiteralPath $operation.TargetPath -Force
					if (Test-Path -LiteralPath $operation.TargetPath) { throw 'rollback removal failed' }
				}
			} catch {
				$rollbackErrors += "$($operation.TargetPath): $($_.Exception.Message)"
			}
		}
		try {
			if ($existingReceipt) {
				Write-LausudoJsonAtomic -Value $existingReceipt -Path $receiptPath
			} elseif (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
				Remove-Item -LiteralPath $receiptPath -Force
			}
		} catch {
			$rollbackErrors += "receipt: $($_.Exception.Message)"
		}
		if ($rollbackErrors.Count -gt 0) {
			throw ("Installation failed: {0} Rollback also reported: {1}" -f $installError.Message, ($rollbackErrors -join '; '))
		}
		throw $installError
	}

	return [pscustomobject]@{
		Action = $Action
		Changed = $changed
		Receipt = if ($changed) { $receiptPath } else { $null }
		FileCount = $entries.Count
	}
}

function Invoke-LausudoUninstall {
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[Parameter(Mandatory = $true)] [System.Management.Automation.PSCmdlet] $Cmdlet
	)

	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot) -WowPath $WowPath
	$clientId = Get-LausudoClientId -WowPath $WowPath
	$receiptPath = Get-LausudoReceiptPath -ClientId $clientId
	$receipt = Read-LausudoReceipt -Path $receiptPath
	if (-not $receipt) {
		return [pscustomobject]@{ Action = 'Uninstall'; Changed = $false; Conflicts = @(); Message = 'No active receipt exists for this client.' }
	}
	$originalReceipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
	$conflicts = @()
	$changed = $false
	$remainingEntries = @()
	$actions = @()

	foreach ($entry in @($receipt.files)) {
		if (-not $entry.owned) { continue }
		$componentId = if ($entry.PSObject.Properties.Name -contains 'componentId') { [string]$entry.componentId } else { 'legacy-ui' }
		Assert-LausudoInstallRelativePath -Path ([string]$entry.targetRelative) -ComponentId $componentId
		$target = Get-LausudoFullPath -Path (Join-Path $WowPath ([string]$entry.targetRelative))
		if (-not (Test-LausudoPathContainment -Parent $WowPath -Child $target)) { throw "Receipt target escapes the WoW directory: $target" }
		Assert-LausudoNoReparsePoint -Root $WowPath -Path $target
		if ($entry.beforeExisted) { Get-LausudoReceiptBackupPath -Receipt $receipt -Entry $entry | Out-Null }
	}

	foreach ($entry in @($receipt.files)) {
		if (-not $entry.owned) { continue }
		$target = Get-LausudoFullPath -Path (Join-Path $WowPath ([string]$entry.targetRelative))
		if (Test-Path -LiteralPath $target -PathType Container) {
			$conflicts += [pscustomobject]@{ Path = $entry.targetRelative; Reason = 'Expected file path is now a directory; preserved.' }
			$remainingEntries += $entry
			continue
		}
		if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
			if (-not $entry.beforeExisted) { continue }
			$backup = Get-LausudoReceiptBackupPath -Receipt $receipt -Entry $entry
			if (-not $backup -or -not (Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-LausudoFileHash -Path $backup) -ne ([string]$entry.beforeHash).ToLowerInvariant()) {
				$conflicts += [pscustomobject]@{ Path = $entry.targetRelative; Reason = 'Installed file is missing and its original backup is unavailable or invalid.' }
				$remainingEntries += $entry
				continue
			}
			if ($Cmdlet.ShouldProcess($target, 'Restore missing pre-installation file')) {
				$actions += [pscustomobject]@{
					Mode = 'Restore'
					TargetPath = $target
					TargetRelative = [string]$entry.targetRelative
					TargetExisted = $false
					CurrentHash = $null
					BackupPath = $backup
					ExpectedHash = ([string]$entry.beforeHash).ToLowerInvariant()
				}
			} else {
				$remainingEntries += $entry
			}
			continue
		}
		$currentHash = Get-LausudoFileHash -Path $target
		if ($currentHash -ne ([string]$entry.installedHash).ToLowerInvariant()) {
			$conflicts += [pscustomobject]@{ Path = $entry.targetRelative; Reason = 'File changed after installation; preserved.' }
			$remainingEntries += $entry
			continue
		}

		if ($entry.beforeExisted) {
			$backup = Get-LausudoReceiptBackupPath -Receipt $receipt -Entry $entry
			if (-not $backup -or -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
				$conflicts += [pscustomobject]@{ Path = $entry.targetRelative; Reason = 'Verified backup is missing; installed file preserved.' }
				$remainingEntries += $entry
				continue
			}
			if ((Get-LausudoFileHash -Path $backup) -ne ([string]$entry.beforeHash).ToLowerInvariant()) {
				$conflicts += [pscustomobject]@{ Path = $entry.targetRelative; Reason = 'Backup hash mismatch; installed file preserved.' }
				$remainingEntries += $entry
				continue
			}
			if ($Cmdlet.ShouldProcess($target, 'Restore pre-installation file')) {
				$actions += [pscustomobject]@{
					Mode = 'Restore'
					TargetPath = $target
					TargetRelative = [string]$entry.targetRelative
					TargetExisted = $true
					CurrentHash = $currentHash
					BackupPath = $backup
					ExpectedHash = ([string]$entry.beforeHash).ToLowerInvariant()
				}
			} else {
				$remainingEntries += $entry
			}
		} elseif ($Cmdlet.ShouldProcess($target, 'Remove receipt-owned file')) {
			$actions += [pscustomobject]@{
				Mode = 'Remove'
				TargetPath = $target
				TargetRelative = [string]$entry.targetRelative
				TargetExisted = $true
				CurrentHash = $currentHash
				BackupPath = $null
				ExpectedHash = $null
			}
		} else {
			$remainingEntries += $entry
		}
	}

	if ($WhatIfPreference) {
		return [pscustomobject]@{ Action = 'Uninstall'; Changed = $false; Conflicts = @($conflicts); Receipt = $receiptPath }
	}

	$rollbackRoot = Join-Path $stateRoot ("UninstallRollback\$clientId\" + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
	$historyPath = $null
	$completed = @()
	$preserveRollback = $false
	try {
		if ($actions.Count -gt 0) {
			Assert-LausudoNoReparsePoint -Root $stateRoot -Path $rollbackRoot
			New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
			Assert-LausudoNoReparsePoint -Root $stateRoot -Path $rollbackRoot
		}
		foreach ($actionItem in $actions) {
			Assert-LausudoNoReparsePoint -Root $WowPath -Path $actionItem.TargetPath
			if ($actionItem.TargetExisted) {
				if (-not (Test-Path -LiteralPath $actionItem.TargetPath -PathType Leaf) -or
					(Get-LausudoFileHash -Path $actionItem.TargetPath) -ne $actionItem.CurrentHash) {
					throw "A receipt-owned target changed during uninstall planning: $($actionItem.TargetRelative)"
				}
				$rollbackPath = Get-LausudoFullPath -Path (Join-Path $rollbackRoot $actionItem.TargetRelative)
				Assert-LausudoNoReparsePoint -Root $rollbackRoot -Path $rollbackPath
				New-Item -ItemType Directory -Path (Split-Path -Parent $rollbackPath) -Force | Out-Null
				Assert-LausudoNoReparsePoint -Root $rollbackRoot -Path $rollbackPath
				Copy-Item -LiteralPath $actionItem.TargetPath -Destination $rollbackPath
				if ((Get-LausudoFileHash -Path $rollbackPath) -ne $actionItem.CurrentHash) {
					throw "Uninstall rollback snapshot verification failed: $($actionItem.TargetRelative)"
				}
				$actionItem | Add-Member -NotePropertyName RollbackPath -NotePropertyValue $rollbackPath
			} else {
				if (Test-Path -LiteralPath $actionItem.TargetPath) {
					throw "A missing receipt-owned target reappeared during uninstall planning: $($actionItem.TargetRelative)"
				}
				$actionItem | Add-Member -NotePropertyName RollbackPath -NotePropertyValue $null
			}
		}

		foreach ($actionItem in $actions) {
			Assert-LausudoNoReparsePoint -Root $WowPath -Path $actionItem.TargetPath
			if ($actionItem.TargetExisted) {
				if (-not (Test-Path -LiteralPath $actionItem.TargetPath -PathType Leaf) -or
					(Get-LausudoFileHash -Path $actionItem.TargetPath) -ne $actionItem.CurrentHash) {
					throw "A receipt-owned target changed before its uninstall operation: $($actionItem.TargetRelative)"
				}
			} elseif (Test-Path -LiteralPath $actionItem.TargetPath) {
				throw "A missing receipt-owned target reappeared before its uninstall operation: $($actionItem.TargetRelative)"
			}
			$completed += $actionItem
			if ($actionItem.Mode -eq 'Restore') {
				$targetParent = Split-Path -Parent $actionItem.TargetPath
				if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
					New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
				}
				Assert-LausudoNoReparsePoint -Root $WowPath -Path $actionItem.TargetPath
				Copy-Item -LiteralPath $actionItem.BackupPath -Destination $actionItem.TargetPath -Force
				if ((Get-LausudoFileHash -Path $actionItem.TargetPath) -ne $actionItem.ExpectedHash) {
					throw "Restored file failed SHA-256 verification: $($actionItem.TargetRelative)"
				}
			} else {
				Remove-Item -LiteralPath $actionItem.TargetPath -Force
				if (Test-Path -LiteralPath $actionItem.TargetPath) {
					throw "Receipt-owned file could not be removed: $($actionItem.TargetRelative)"
				}
			}
		}
		$changed = $actions.Count -gt 0

		Assert-LausudoNoReparsePoint -Root $stateRoot -Path $receiptPath
		if ($remainingEntries.Count -eq 0) {
			$historyRoot = Join-Path (Split-Path -Parent $receiptPath) 'History'
			New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
			Assert-LausudoNoReparsePoint -Root $stateRoot -Path $historyRoot
			$historyPath = Join-Path $historyRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N') + '.json')
			Move-Item -LiteralPath $receiptPath -Destination $historyPath
			if ((Test-Path -LiteralPath $receiptPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
				throw 'The uninstall receipt could not be archived safely.'
			}
		} elseif ($changed) {
			$receipt.files = @($remainingEntries)
			Write-LausudoJsonAtomic -Value $receipt -Path $receiptPath
			$writtenReceipt = Read-LausudoReceipt -Path $receiptPath
			if (-not $writtenReceipt -or @($writtenReceipt.files).Count -ne $remainingEntries.Count) {
				throw 'The conflict receipt failed post-write verification.'
			}
		}
	} catch {
		$uninstallError = $_.Exception
		$rollbackErrors = @()
		for ($index = $completed.Count - 1; $index -ge 0; $index--) {
			$actionItem = $completed[$index]
			try {
				Assert-LausudoNoReparsePoint -Root $WowPath -Path $actionItem.TargetPath
				if ($actionItem.TargetExisted) {
					Copy-Item -LiteralPath $actionItem.RollbackPath -Destination $actionItem.TargetPath -Force
					if ((Get-LausudoFileHash -Path $actionItem.TargetPath) -ne $actionItem.CurrentHash) {
						throw 'hash mismatch after rollback'
					}
				} elseif (Test-Path -LiteralPath $actionItem.TargetPath -PathType Leaf) {
					Remove-Item -LiteralPath $actionItem.TargetPath -Force
				}
			} catch {
				$rollbackErrors += "$($actionItem.TargetRelative): $($_.Exception.Message)"
			}
		}
		try {
			if ($historyPath -and (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
				if (Test-Path -LiteralPath $receiptPath) {
					Remove-Item -LiteralPath $historyPath -Force
				} else {
					Move-Item -LiteralPath $historyPath -Destination $receiptPath
				}
			}
			Write-LausudoJsonAtomic -Value $originalReceipt -Path $receiptPath
		} catch {
			$rollbackErrors += "receipt: $($_.Exception.Message)"
		}
		if ($rollbackErrors.Count -gt 0) {
			$preserveRollback = $true
			throw ("Uninstall failed: {0} Rollback also reported: {1}. Recovery snapshots were preserved at {2}" -f $uninstallError.Message, ($rollbackErrors -join '; '), $rollbackRoot)
		}
		throw $uninstallError
	} finally {
		if (-not $preserveRollback -and
			(Test-LausudoPathContainment -Parent (Join-Path $stateRoot 'UninstallRollback') -Child $rollbackRoot) -and
			(Test-Path -LiteralPath $rollbackRoot -PathType Container)) {
			Assert-LausudoNoReparsePoint -Root $stateRoot -Path $rollbackRoot
			Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
		}
	}

	return [pscustomobject]@{ Action = 'Uninstall'; Changed = $changed; Conflicts = @($conflicts); Receipt = $receiptPath }
}

function Get-LausudoHdState {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[ValidatePattern('^[a-z]{2}[A-Z]{2}$')] [string] $Locale = 'enUS',
		[switch] $FullHash,
		[string] $ManifestPath = (Join-Path $script:RepositoryRoot 'manifests\hd-patches.json')
	)

	$root = Get-LausudoFullPath -Path $WowPath
	if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "WoW directory not found: $root" }
	$dataRoot = Join-Path $root 'Data'
	if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) { throw "Data directory not found: $dataRoot" }
	Assert-LausudoNoReparsePoint -Root $root -Path $dataRoot
	$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
	if (@($manifest.locales) -notcontains $Locale) { throw "Unsupported locale: $Locale" }
	$results = @()

	foreach ($patch in @($manifest.patches)) {
		$template = [string]$patch.pathTemplate
		$isLocalized = $template.Contains('{locale}')
		$relative = $template.Replace('{locale}', $Locale)
		try {
			Test-LausudoArchiveEntries -Entry @($relative, ($relative + '.disabled')) | Out-Null
		} catch {
			throw "HD manifest path escapes Data or is unsafe: $relative"
		}
		$enabledPath = Get-LausudoFullPath -Path (Join-Path $dataRoot $relative)
		$disabledPath = $enabledPath + '.disabled'
		if (-not (Test-LausudoPathContainment -Parent $dataRoot -Child $enabledPath)) { throw "HD manifest path escapes Data: $relative" }
		Assert-LausudoNoReparsePoint -Root $dataRoot -Path (Split-Path -Parent $enabledPath)
		$enabledExists = Test-Path -LiteralPath $enabledPath -PathType Leaf
		$disabledExists = Test-Path -LiteralPath $disabledPath -PathType Leaf
		if ($enabledExists) { Assert-LausudoNoReparsePoint -Root $dataRoot -Path $enabledPath }
		if ($disabledExists) { Assert-LausudoNoReparsePoint -Root $dataRoot -Path $disabledPath }
		$actualState = if ($enabledExists -and $disabledExists) { 'duplicate' } elseif ($enabledExists) { 'enabled' } elseif ($disabledExists) { 'disabled' } else { 'missing' }
		$actualPath = if ($enabledExists) { $enabledPath } elseif ($disabledExists) { $disabledPath } else { $null }
		$actualBytes = if ($actualPath) { (Get-Item -LiteralPath $actualPath).Length } else { $null }
		$expectedBytes = $patch.bytes
		if ($patch.PSObject.Properties.Name -contains 'bytesByLocale' -and $patch.bytesByLocale) {
			$expectedBytes = $patch.bytesByLocale.$Locale
		}
		$stateMatches = $actualState -eq [string]$patch.state
		$sizeMatches = $null -ne $actualBytes -and $null -ne $expectedBytes -and [int64]$actualBytes -eq [int64]$expectedBytes
		$actualHash = if ($FullHash -and $actualPath) { Get-LausudoFileHash -Path $actualPath } else { $null }
		$expectedHash = if ($patch.PSObject.Properties.Name -contains 'sha256') { $patch.sha256 } else { $null }
		if ($patch.PSObject.Properties.Name -contains 'sha256ByLocale' -and $patch.sha256ByLocale) {
			$localeHashProperty = $patch.sha256ByLocale.PSObject.Properties[$Locale]
			$expectedHash = if ($localeHashProperty) { $localeHashProperty.Value } else { $null }
		}
		$hashMatches = if (-not $FullHash) { $null } elseif (-not $expectedHash) { $null } else { $actualHash -eq ([string]$expectedHash).ToLowerInvariant() }
		$results += [pscustomobject]@{
			Id = [string]$patch.id
			Label = [string]$patch.label
			Locale = if ($isLocalized) { $Locale } else { $null }
			RelativePath = $relative
			ExpectedState = [string]$patch.state
			ActualState = $actualState
			StateMatches = $stateMatches
			ExpectedBytes = $expectedBytes
			ActualBytes = $actualBytes
			SizeMatches = $sizeMatches
			ExpectedSha256 = $expectedHash
			ActualSha256 = $actualHash
			HashMatches = $hashMatches
		}
	}
	return $results
}

function Get-LausudoAuditReport {
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[Parameter(Mandatory = $true)] [object] $Manifest,
		[Parameter(Mandatory = $true)] [string[]] $Components,
		[Parameter(Mandatory = $true)] [string] $Locale,
		[switch] $FullHash
	)

	$results = @()
	if ($Components -contains 'UI') {
		foreach ($component in @($Manifest.components | Where-Object { $_.id -in $script:UiComponentIds -or $_.id -in @('weakauras', 'elvui', 'project-zidras') })) {
			$expected = @($component.expectedRoots)
			$present = $expected.Count -gt 0
			foreach ($relative in $expected) {
				Assert-LausudoPublicRelativePath -Path ([string]$relative)
				if (-not (Test-Path -LiteralPath (Join-Path $WowPath ([string]$relative)))) { $present = $false }
			}
			$results += [pscustomobject]@{ Category = 'Component'; Id = $component.id; Distribution = $component.distribution; Present = $present }
		}
	}
	if ($Components -contains 'GraphicsRuntime') {
		$runtime = Join-Path $WowPath 'd3d9.dll'
		$results += [pscustomobject]@{ Category = 'GraphicsRuntime'; Id = 'dxvk'; Distribution = 'download'; Present = (Test-Path -LiteralPath $runtime -PathType Leaf) }
	}
	if ($Components -contains 'ReShadePreset') {
		$results += [pscustomobject]@{ Category = 'ReShadePreset'; Id = 'reshade-preset'; Distribution = 'gated'; Present = $false; Message = 'No preset is bundled pending documented redistribution permission.' }
	}
	$hd = @(Get-LausudoHdState -WowPath $WowPath -Locale $Locale -FullHash:$FullHash)
	return [pscustomobject]@{ Action = 'Audit'; Components = $results; HdPatches = $hd }
}

function Invoke-LausudoSuite {
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param(
		[Parameter(Mandatory = $true)] [string] $WowPath,
		[ValidateSet('Audit', 'Install', 'Repair', 'Uninstall')] [string] $Action = 'Audit',
		[ValidateSet('UI', 'ReShadePreset', 'GraphicsRuntime')] [string[]] $Components = @('UI'),
		[ValidatePattern('^[a-z]{2}[A-Z]{2}$')] [string] $Locale = 'enUS',
		[switch] $FullHash,
		[switch] $Offline
	)

	$client = Test-LausudoWowExecutable -WowPath $WowPath
	$root = $client.WowPath
	$manifest = Get-LausudoSuiteManifest
	if (@($manifest.target.locales) -notcontains $Locale) { throw "Unsupported locale: $Locale" }
	$components = @($Components | Select-Object -Unique)
	if ($Action -eq 'Audit') {
		return Get-LausudoAuditReport -WowPath $root -Manifest $manifest -Components $components -Locale $Locale -FullHash:$FullHash
	}

	Assert-LausudoClientNotRunning -WowExecutable $client.Executable
	$stateRoot = Assert-LausudoStateRoot -StateRoot (Get-LausudoStateRoot) -WowPath $root
	if ($Action -eq 'Uninstall') {
		return Invoke-LausudoUninstall -WowPath $root -Cmdlet $PSCmdlet
	}
	if ($components -contains 'ReShadePreset') {
		throw 'The ReShade preset is unavailable until its redistribution permission is documented. No preset or shader files are bundled.'
	}

	$plan = @()
	if ($components -contains 'UI') {
		$plan += @(New-LausudoBundledFilePlan -WowPath $root -Manifest $manifest)
	}
	$prepared = @()
	$runtimePreview = $false
	try {
		if ($components -contains 'GraphicsRuntime') {
			$runtimeTarget = Join-Path $root 'd3d9.dll'
			if ($PSCmdlet.ShouldProcess($runtimeTarget, 'Prepare pinned official DXVK x86 D3D9 runtime')) {
				$dxvk = Get-LausudoDxvkPlan -WowPath $root -Manifest $manifest -Offline:$Offline
				$plan += $dxvk
				$prepared += $dxvk.PreparedRoot
			} else {
				$runtimePreview = $true
			}
		}
		if ($plan.Count -eq 0) {
			if ($runtimePreview) {
				return [pscustomobject]@{ Action = $Action; Changed = $false; RuntimePreview = 'Pinned DXVK x86 D3D9 runtime'; FileCount = 1 }
			}
			throw 'No installable components were selected.'
		}
		$result = Invoke-LausudoInstallPlan -Plan $plan -WowPath $root -Manifest $manifest -Action $Action -Cmdlet $PSCmdlet
		if ($runtimePreview) {
			return [pscustomobject]@{ Action = $Action; Changed = $result.Changed; UiResult = $result; RuntimePreview = 'Pinned DXVK x86 D3D9 runtime' }
		}
		return $result
	} finally {
		foreach ($path in $prepared) {
			$preparedParent = Join-Path $stateRoot 'Prepared'
			if ($path -and (Test-LausudoPathContainment -Parent $preparedParent -Child $path) -and (Test-Path -LiteralPath $path)) {
				Assert-LausudoNoReparsePoint -Root $stateRoot -Path $path
				Remove-Item -LiteralPath $path -Recurse -Force
			}
		}
	}
}

Export-ModuleMember -Function @(
	'Get-LausudoSuiteManifest',
	'Get-LausudoHdState',
	'Invoke-LausudoSuite',
	'New-LausudoBundledFilePlan',
	'Test-LausudoArchiveEntries',
	'Test-LausudoPathContainment',
	'Test-LausudoWowExecutable'
)
