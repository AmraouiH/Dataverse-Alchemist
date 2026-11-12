#Requires -Version 7.0
<#
.SYNOPSIS
    Shows what the agent has learned (current user and project), or removes a lesson with -RemoveId.
.EXAMPLE
    Get-AlchemistKnowledge.ps1
    Get-AlchemistKnowledge.ps1 -Category form-layout
    Get-AlchemistKnowledge.ps1 -RemoveId 1a2b3c4d
#>
[CmdletBinding()]
param(
    [string]$Category,
    [string]$RemoveId,
    [string]$UserId,
    [string]$ConfigPath,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$sources = @(
    @{ scope = 'User'; path = (Get-AlchemistKnowledgePath -Scope User -UserId $UserId -ConfigPath $ConfigPath) }
)
try { $sources += @{ scope = 'Project'; path = (Get-AlchemistKnowledgePath -Scope Project -ConfigPath $ConfigPath) } } catch { Write-Verbose 'No project: personal knowledge only.' }

if ($RemoveId) {
    foreach ($source in $sources) {
        $entries = @(Read-AlchemistKnowledge -Path $source.path)
        $kept = @($entries | Where-Object { $_.id -ne $RemoveId })
        if ($kept.Count -ne $entries.Count) {
            Save-AlchemistKnowledge -Path $source.path -Entries $kept
            [ordered]@{ removed = $RemoveId; scope = $source.scope } | ConvertTo-Json
            return
        }
    }
    throw "Lesson '$RemoveId' not found."
}

$all = foreach ($source in $sources) {
    foreach ($entry in (Read-AlchemistKnowledge -Path $source.path)) {
        if ($Category -and $entry.category -ne $Category) { continue }
        [pscustomobject]@{ scope = $source.scope; id = $entry.id; category = $entry.category; lesson = $entry.lesson; count = [int]$entry.count; lastSeen = $entry.lastSeen }
    }
}
$all = @($all)
if ($Json) { $all | ConvertTo-Json -Depth 4; return }
if (-not $all.Count) { 'No lesson recorded.'; return }

foreach ($group in ($all | Group-Object { "$($_.scope) / $($_.category)" } | Sort-Object Name)) {
    "## $($group.Name)"
    foreach ($item in ($group.Group | Sort-Object count -Descending)) {
        # Confirmed from 3 signals: apply by default. Below that: just a hint.
        $level = if ($item.count -ge 3) { 'confirmed' } else { 'observed' }
        "- [$($item.id)] $($item.lesson) ($level, $($item.count)x, last signal $($item.lastSeen))"
    }
    ''
}
