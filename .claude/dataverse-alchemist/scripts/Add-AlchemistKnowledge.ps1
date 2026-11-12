#Requires -Version 7.0
<#
.SYNOPSIS
    Records what the agent learned about a user or a project. A lesson already known is reinforced, not duplicated.
    Refuses secrets and personal data.
.EXAMPLE
    Add-AlchemistKnowledge.ps1 -Scope User -Category form-layout -Signal chosen -Lesson "Prefers a single-screen form in 3 columns" -IssueKey CRM-1 -Note "Option A chosen"
#>
[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [Parameter(Mandatory)][ValidateSet('communication', 'form-layout', 'naming', 'code-style', 'testing', 'delivery', 'workflow', 'data-model')][string]$Category,
    # satisfied: satisfaction expressed; chosen: option chosen; corrected: the user corrected the agent.
    [Parameter(Mandatory)][ValidateSet('satisfied', 'chosen', 'corrected')][string]$Signal,
    [Parameter(Mandatory)][string]$Lesson,
    [string]$IssueKey,
    # What triggered the lesson, in one sentence.
    [string]$Note,
    [string]$UserId,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$text = "$Lesson $Note"
if ($text -match '(?i)\b(password|mot de passe|secret|token|api[_-]?key|bearer|client[_-]?secret)\b\s*[:=]') { throw "Refused: the lesson seems to contain a secret." }
if ($text -match '[\w.+-]+@[\w-]+\.[\w.-]+') { throw "Refused: no email address in the knowledge base." }
if ($text -match '(?i)\beyJ[\w-]{10,}\.|\b[0-9a-f]{32,}\b') { throw "Refused: the lesson seems to contain a token." }
if ($Lesson.Trim().Length -lt 10) { throw "Lesson too short: describe a reusable behavior." }

$path = Get-AlchemistKnowledgePath -Scope $Scope -UserId $UserId -ConfigPath $ConfigPath
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($entry in (Read-AlchemistKnowledge -Path $path)) { $entries.Add($entry) }

$normalized = ($Lesson.Trim() -replace '\s+', ' ').ToLowerInvariant()
$existing = $entries | Where-Object { $_.category -eq $Category -and (($_.lesson.Trim() -replace '\s+', ' ').ToLowerInvariant()) -eq $normalized } | Select-Object -First 1
$today = (Get-Date).ToString('yyyy-MM-dd')
$evidence = [ordered]@{ date = $today; signal = $Signal; issue = $IssueKey; note = $Note }

if ($existing) {
    $existing.count = [int]$existing.count + 1
    $existing.lastSeen = $today
    $existing.evidence = @(@($existing.evidence) + $evidence | Select-Object -Last 10)
    $action = 'reinforced'
    $id = $existing.id
}
else {
    $id = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    $entries.Add([ordered]@{ id = $id; category = $Category; lesson = $Lesson.Trim(); count = 1; firstSeen = $today; lastSeen = $today; evidence = @($evidence) })
    $action = 'added'
}
Save-AlchemistKnowledge -Path $path -Entries $entries
[ordered]@{ action = $action; id = $id; scope = $Scope; category = $Category; file = $path } | ConvertTo-Json
