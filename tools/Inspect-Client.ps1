# Author: Neil Mitchell
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ClientPath)
$ErrorActionPreference = 'Stop'
$client = Get-Item -LiteralPath $ClientPath -ErrorAction Stop
if (-not $client.PSIsContainer) { throw 'ClientPath must be a folder.' }
if (-not (Test-Path -LiteralPath (Join-Path $client.FullName 'WoW.exe') -PathType Leaf)) {
    throw 'WoW.exe was not found in that folder.'
}
$catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\suite.json') -Raw | ConvertFrom-Json
foreach ($module in $catalog.modules) {
    foreach ($addon in $module.addons) {
        $name = ($addon -split '/')[-1]
        [pscustomobject]@{
            Module = $module.id
            Addon = $name
            Installed = Test-Path -LiteralPath (Join-Path $client.FullName "Interface\AddOns\$name\$name.toc") -PathType Leaf
            ExternalDependencies = $module.external -join ', '
        }
    }
}
# Metadata only: no credentials, SavedVariables or client configuration are opened.
