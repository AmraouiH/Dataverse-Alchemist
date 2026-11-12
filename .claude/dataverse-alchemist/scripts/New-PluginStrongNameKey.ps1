#Requires -Version 7.0
<#
.SYNOPSIS
    Creates the signing key of a plugin assembly (.snk): Dataverse refuses an unsigned assembly.
    An existing key is never replaced, as it would change the identity of the assembly already registered.
.EXAMPLE
    New-PluginStrongNameKey.ps1 -Path plugins/Alchemist.Plugins/Alchemist.Plugins.snk
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'

$target = [IO.Path]::GetFullPath($Path)
if (Test-Path -LiteralPath $target) { throw "Key already exists: $target" }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))

$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
try { [IO.File]::WriteAllBytes($target, $rsa.ExportCspBlob($true)) }
finally { $rsa.Dispose() }
[ordered]@{ file = $target; bytes = (Get-Item -LiteralPath $target).Length } | ConvertTo-Json
