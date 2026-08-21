[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[string]$InputPath,

	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[string]$ProfileName,

	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$nodeScript = Join-Path $PSScriptRoot 'export-visual-profile.mjs'

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
	throw 'The explicit SavedVariables input file does not exist.'
}
if (Test-Path -LiteralPath $OutputPath) {
	throw 'The output path already exists; refusing to overwrite it.'
}

$node = Get-Command node -ErrorAction Stop
& $node.Source $nodeScript --input $InputPath --profile $ProfileName --output $OutputPath --repo-root $repoRoot
if ($LASTEXITCODE -ne 0) { throw 'The visual-profile exporter failed closed.' }
