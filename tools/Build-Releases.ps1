# Author: Neil Mitchell
[CmdletBinding()]
param([string[]]$Module)
$ErrorActionPreference = 'Stop'
$launcher = Get-Command py -ErrorAction Stop
$tool = Join-Path $PSScriptRoot 'suite.py'
$arguments = @('-3', $tool, 'build')
foreach ($item in $Module) { $arguments += @('--module', $item) }
& $launcher.Source @arguments
if ($LASTEXITCODE -ne 0) { throw 'Suite package validation/build failed.' }
