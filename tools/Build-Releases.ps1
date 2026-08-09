[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $repoRoot 'dist'
$verificationRoot = Join-Path $outputRoot 'verification'
$python = Get-Command py -ErrorAction Stop

& $python.Source -3.13 (Join-Path $PSScriptRoot 'Generate-CrispFctAtlas.py')
if ($LASTEXITCODE -ne 0) { throw 'Crisp FCT atlas generation failed.' }

New-Item -ItemType Directory -Force -Path $outputRoot, $verificationRoot | Out-Null
Get-ChildItem -LiteralPath $outputRoot -Filter '*.zip' -File | Remove-Item -Force
Get-ChildItem -LiteralPath $verificationRoot -Force | Remove-Item -Recurse -Force

$packages = @(
	@{ Name = 'Warmane-Font-Pack-1.0.0'; Addon = 'WarmaneFontPack' },
	@{ Name = 'CrispFCT-Warmane-3.3.5a-1.0.0'; Addon = 'CrispFCT' }
)

foreach ($package in $packages) {
	$stage = Join-Path $verificationRoot $package.Name
	$addonTarget = Join-Path $stage ('Interface\AddOns\' + $package.Addon)
	New-Item -ItemType Directory -Force -Path $addonTarget | Out-Null
	Get-ChildItem -LiteralPath (Join-Path $repoRoot ('addons\' + $package.Addon)) -Force |
		Copy-Item -Destination $addonTarget -Recurse
	Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $stage 'README.md')
	Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stage 'LICENSE')
	if ($package.Addon -eq 'WarmaneFontPack') {
		Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD-PARTY-NOTICES.md') -Destination (Join-Path $stage 'THIRD-PARTY-NOTICES.md')
	}
	if ($package.Addon -eq 'CrispFCT') {
		New-Item -ItemType Directory -Force -Path (Join-Path $stage 'LICENSES') | Out-Null
		Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses\OFL-PTSansNarrow.txt') -Destination (Join-Path $stage 'LICENSES\OFL-PTSansNarrow.txt')
	}
	Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $outputRoot ($package.Name + '.zip')) -Force
}

Get-ChildItem -LiteralPath $outputRoot -Filter '*.zip' -File |
	Get-FileHash -Algorithm SHA256 |
	Select-Object @{Name='File'; Expression = { $_.Path | Split-Path -Leaf } }, Hash |
	Export-Csv -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.csv') -NoTypeInformation
