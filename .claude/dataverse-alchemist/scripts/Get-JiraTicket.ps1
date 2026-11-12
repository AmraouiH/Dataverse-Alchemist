#Requires -Version 7.0
<#
.SYNOPSIS
    Retrieves a Jira ticket and saves it in .alchemist/runs/<KEY>/ (ticket.json + ticket.md).
.EXAMPLE
    pwsh -NoProfile -File Get-JiraTicket.ps1 -IssueKey CRM-123 -DownloadAttachments
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [string]$ConfigPath,
    [switch]$DownloadAttachments,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$IssueKey = $IssueKey.ToUpperInvariant()
$isLocal = Test-AlchemistLocalTickets -Config $config
$baseUrl = if ($isLocal) { '' } else { (Get-AlchemistSetting $config 'jira.baseUrl' -Required).TrimEnd('/') }
$acceptanceField = Get-AlchemistSetting $config 'jira.acceptanceCriteriaField'
$baseBranchField = Get-AlchemistSetting $config 'jira.baseBranchField'
$extraFields = @(Get-AlchemistSetting $config 'jira.extraFields' -Default @())
$maxComments = [int](Get-AlchemistSetting $config 'jira.maxComments' -Default 20)

# Converts an ADF document (API v3) or a custom field value to text.
function ConvertTo-PlainText {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary] -and $Value -isnot [pscustomobject]) {
        return (@($Value | ForEach-Object { ConvertTo-PlainText $_ }) -join ', ')
    }
    $props = $Value.PSObject.Properties.Name
    if ($props -contains 'type' -and $props -contains 'content') {
        $sb = [Text.StringBuilder]::new()
        function Walk($node, $sb) {
            if ($node.type -eq 'text') { [void]$sb.Append($node.text); return }
            if ($node.type -eq 'hardBreak') { [void]$sb.Append("`n"); return }
            if ($node.type -eq 'listItem') { [void]$sb.Append('- ') }
            if ($node.PSObject.Properties.Name -contains 'content') { foreach ($child in $node.content) { Walk $child $sb } }
            if ($node.type -in 'paragraph', 'heading', 'listItem', 'codeBlock', 'tableRow') { [void]$sb.Append("`n") }
        }
        Walk $Value $sb
        return $sb.ToString().Trim()
    }
    foreach ($candidate in 'value', 'name', 'displayName') {
        if ($props -contains $candidate) { return [string]$Value.$candidate }
    }
    return ($Value | ConvertTo-Json -Depth 10 -Compress)
}

$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey

if ($isLocal) {
    $source = Read-AlchemistLocalTickets -Config $config | Where-Object { $_.key -eq $IssueKey } | Select-Object -First 1
    if (-not $source) { throw "Local ticket '$IssueKey' not found in $(Get-AlchemistLocalTicketsPath -Config $config)." }
    $ticket = [ordered]@{
        key = $source.key; url = "local:$($source.key)"; summary = $source.summary; issueType = $source.issueType; status = $source.status
        priority = $source.priority; labels = @($source.labels); components = @($source.components); fixVersions = @($source.fixVersions)
        assignee = $source.assignee; reporter = $source.reporter; parent = $null; description = $source.description
        acceptanceCriteria = $source.acceptanceCriteria; baseBranchHint = $source.baseBranch; extraFields = [ordered]@{}
        subtasks = @(); links = @(); attachments = @(); comments = @($source.comments | Where-Object { $_ })
    }
}
else {
$fields = @('summary', 'description', 'issuetype', 'status', 'priority', 'labels', 'components', 'fixVersions',
    'assignee', 'reporter', 'subtasks', 'issuelinks', 'attachment', 'comment', 'parent') + $extraFields
if ($acceptanceField) { $fields += $acceptanceField }
if ($baseBranchField) { $fields += $baseBranchField }

$issue = Invoke-JiraRequest -Config $config -Path "issue/$($IssueKey)?fields=$($fields -join ',')"
$f = $issue.fields

$ticket = [ordered]@{
    key                = $issue.key
    url                = "$baseUrl/browse/$($issue.key)"
    summary            = $f.summary
    issueType          = $f.issuetype.name
    status             = $f.status.name
    priority           = if ($f.priority) { $f.priority.name } else { $null }
    labels             = @($f.labels)
    components         = @($f.components | ForEach-Object { $_.name })
    fixVersions        = @($f.fixVersions | ForEach-Object { $_.name })
    assignee           = if ($f.assignee) { $f.assignee.displayName } else { $null }
    reporter           = if ($f.reporter) { $f.reporter.displayName } else { $null }
    parent             = if ($f.parent) { "$($f.parent.key) - $($f.parent.fields.summary)" } else { $null }
    description        = ConvertTo-PlainText $f.description
    acceptanceCriteria = if ($acceptanceField) { ConvertTo-PlainText $f.$acceptanceField } else { $null }
    baseBranchHint     = if ($baseBranchField) { ConvertTo-PlainText $f.$baseBranchField } else { $null }
    extraFields        = [ordered]@{}
    subtasks           = @($f.subtasks | ForEach-Object { [ordered]@{ key = $_.key; summary = $_.fields.summary; status = $_.fields.status.name } })
    links              = @($f.issuelinks | ForEach-Object {
            $linked = if ($_.outwardIssue) { $_.outwardIssue } else { $_.inwardIssue }
            $label = if ($_.outwardIssue) { $_.type.outward } else { $_.type.inward }
            [ordered]@{ relation = $label; key = $linked.key; summary = $linked.fields.summary; status = $linked.fields.status.name }
        })
    attachments        = @()
    comments           = @()
}
foreach ($name in $extraFields) { $ticket.extraFields[$name] = ConvertTo-PlainText $f.$name }

$attachmentFolder = Join-Path $runFolder 'attachments'
foreach ($attachment in @($f.attachment)) {
    if (-not $attachment) { continue }
    $entry = [ordered]@{ filename = $attachment.filename; mimeType = $attachment.mimeType; size = $attachment.size; url = $attachment.content; localPath = $null }
    if ($DownloadAttachments) {
        New-Item -ItemType Directory -Path $attachmentFolder -Force | Out-Null
        $target = Join-Path $attachmentFolder $attachment.filename
        Invoke-WebRequest -Uri $attachment.content -Headers (Get-JiraAuthHeaders -Config $config) -OutFile $target | Out-Null
        $entry.localPath = $target
    }
    $ticket.attachments += $entry
}

$allComments = @($f.comment.comments)
$ticket.comments = @($allComments | Select-Object -Last $maxComments | ForEach-Object {
        [ordered]@{ author = $_.author.displayName; created = $_.created; body = ConvertTo-PlainText $_.body }
    })

}

$ticket | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runFolder 'ticket.json') -Encoding utf8

$md = [Text.StringBuilder]::new()
[void]$md.AppendLine("# $($ticket.key) — $($ticket.summary)")
[void]$md.AppendLine()
[void]$md.AppendLine("- **Link**: $($ticket.url)")
[void]$md.AppendLine("- **Type**: $($ticket.issueType) | **Status**: $($ticket.status) | **Priority**: $($ticket.priority)")
[void]$md.AppendLine("- **Labels**: $($ticket.labels -join ', ') | **Components**: $($ticket.components -join ', ') | **Fix versions**: $($ticket.fixVersions -join ', ')")
if ($ticket.parent) { [void]$md.AppendLine("- **Parent**: $($ticket.parent)") }
if ($ticket.baseBranchHint) { [void]$md.AppendLine("- **Branch given in Jira**: $($ticket.baseBranchHint)") }
[void]$md.AppendLine()
[void]$md.AppendLine('## Description')
[void]$md.AppendLine($ticket.description ?? '_(empty)_')
if ($ticket.acceptanceCriteria) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Acceptance criteria")
    [void]$md.AppendLine($ticket.acceptanceCriteria)
}
foreach ($name in $ticket.extraFields.Keys) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## $name")
    [void]$md.AppendLine($ticket.extraFields[$name])
}
if ($ticket.subtasks.Count) {
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Subtasks')
    $ticket.subtasks | ForEach-Object { [void]$md.AppendLine("- $($_.key) [$($_.status)] $($_.summary)") }
}
if ($ticket.links.Count) {
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Linked tickets')
    $ticket.links | ForEach-Object { [void]$md.AppendLine("- $($_.relation) $($_.key) [$($_.status)] $($_.summary)") }
}
if ($ticket.attachments.Count) {
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Attachments')
    $ticket.attachments | ForEach-Object { [void]$md.AppendLine("- $($_.filename) ($($_.mimeType))$(if ($_.localPath) { " -> $($_.localPath)" })") }
}
if ($ticket.comments.Count) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Comments ($($ticket.comments.Count) most recent)")
    $ticket.comments | ForEach-Object {
        [void]$md.AppendLine("### $($_.author) — $($_.created)")
        [void]$md.AppendLine($_.body)
    }
}
$md.ToString() | Set-Content -LiteralPath (Join-Path $runFolder 'ticket.md') -Encoding utf8

if ($Json) { $ticket | ConvertTo-Json -Depth 20 } else { $md.ToString(); "`n_Saved to: $($runFolder)_" }
