#Requires -Version 7.0
<#
.SYNOPSIS
    Adds a comment to a Jira ticket from a text file, optionally with an attachment (e.g. HTML report)
    referenced in the comment. Action visible to the team: only run it after explicit user approval.
.EXAMPLE
    Add-JiraComment.ps1 -IssueKey CRM-123 -BodyFile comment.txt -AttachmentPath .alchemist/runs/CRM-123/report-CRM-123.html -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [Parameter(Mandatory)][string]$BodyFile,
    [string]$AttachmentPath,
    [string]$ConfigPath,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$text = (Get-Content -Raw -LiteralPath $BodyFile).TrimEnd()
$isLocal = Test-AlchemistLocalTickets -Config $config
$apiVersion = Get-AlchemistSetting $config 'jira.apiVersion' -Default '2'
$baseUrl = if ($isLocal) { '' } else { (Get-AlchemistSetting $config 'jira.baseUrl' -Required).TrimEnd('/') }

if ($DryRun) {
    [ordered]@{ dryRun = $true; issue = $IssueKey; attachment = $AttachmentPath; body = $text } | ConvertTo-Json
    return
}

if ($isLocal) {
    # Without Jira, the comment is kept in the local ticket file, with the report path.
    $tickets = @(Read-AlchemistLocalTickets -Config $config)
    $target = $tickets | Where-Object { $_.key -eq $IssueKey.ToUpperInvariant() } | Select-Object -First 1
    if (-not $target) { throw "Local ticket '$IssueKey' not found." }
    $target.comments = @(@($target.comments | Where-Object { $_ }) + [ordered]@{ author = 'Dataverse Alchemist'; created = (Get-Date).ToUniversalTime().ToString('o'); body = $text; attachment = $AttachmentPath })
    Save-AlchemistLocalTickets -Config $config -Tickets $tickets
    Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'jira.comment.local' -Details @{ attachment = $AttachmentPath }
    [ordered]@{ commented = $true; issue = $IssueKey; local = $true; attachment = $AttachmentPath } | ConvertTo-Json
    return
}

$attachment = $null
if ($AttachmentPath) {
    $headers = Get-JiraAuthHeaders -Config $config
    $headers['X-Atlassian-Token'] = 'no-check'
    $uploaded = Invoke-RestMethod -Method Post -Uri "$baseUrl/rest/api/$apiVersion/issue/$IssueKey/attachments" -Headers $headers `
        -Form @{ file = Get-Item -LiteralPath $AttachmentPath }
    $attachment = @($uploaded)[0]
}

if ($apiVersion -eq '3') {
    # ADF: one paragraph per line, then a link to the attachment.
    $content = @($text -split "`r?`n" | ForEach-Object {
            if ($_) { @{ type = 'paragraph'; content = @(@{ type = 'text'; text = $_ }) } } else { @{ type = 'paragraph'; content = @() } }
        })
    if ($attachment) {
        $content += @{ type = 'paragraph'; content = @(@{ type = 'text'; text = "📎 $($attachment.filename)"; marks = @(@{ type = 'link'; attrs = @{ href = $attachment.content } }) }) }
    }
    $body = @{ body = @{ type = 'doc'; version = 1; content = $content } }
}
else {
    # Wiki markup: [^file] creates the link to the ticket attachment.
    $wiki = $text
    if ($attachment) { $wiki += "`n`n[^$($attachment.filename)]" }
    $body = @{ body = $wiki }
}

$result = Invoke-JiraRequest -Config $config -Method POST -Path "issue/$IssueKey/comment" -Body $body
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'jira.comment' -Details @{ commentId = $result.id; attachment = $attachment.filename }
[ordered]@{ commented = $true; issue = $IssueKey; commentId = $result.id; attachment = $attachment.filename; attachmentUrl = $attachment.content } | ConvertTo-Json
