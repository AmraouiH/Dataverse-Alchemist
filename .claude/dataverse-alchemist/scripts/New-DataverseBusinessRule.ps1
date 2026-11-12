#Requires -Version 7.0
<#
.SYNOPSIS
    Creates and activates a simple business rule (scope: all forms) in the ticket solution:
    IF <field> = (or <>) <value> THEN fields required / optional / hidden. No ELSE branch: the server refuses it
    (HTTP 500 "waitStep" on CRM-410); for the reverse case, create a second rule with -ConditionOperator NotEqual.
.DESCRIPTION
    Generates the rule XAML (template taken from a rule created by the designer), then activates it and checks its triggers.
    Richer rules (several conditions, default values, error messages) are left to the designer.
.PARAMETER ConditionType
    OptionSetValue (choice: numeric value), String, Boolean (true/false), Integer.
.EXAMPLE
    New-DataverseBusinessRule.ps1 -Table rhz_servicecontract -Name "End date required when active" -ConditionField rhz_contractstatus -ConditionType OptionSetValue -ConditionValue 911240001 -RequireFields rhz_enddate -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ConditionField,
    [ValidateSet('OptionSetValue', 'String', 'Boolean', 'Integer')][string]$ConditionType = 'OptionSetValue',
    [Parameter(Mandatory)][string]$ConditionValue,
    [ValidateSet('Equal', 'NotEqual')][string]$ConditionOperator = 'Equal',
    [string[]]$RequireFields,
    # Makes fields optional (RequiredLevel None): with -ConditionOperator NotEqual, replaces the Else branch refused by the server
    [string[]]$OptionalFields,
    [string[]]$HideFields,
    [string]$Description,
    [string]$Solution,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey
$Table = $Table.ToLowerInvariant()
$split = { param($list) @($list | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) }
$required = & $split $RequireFields
$hidden = & $split $HideFields
$optional = & $split $OptionalFields
if (-not ($required + $hidden + $optional)) { throw "Give at least -RequireFields, -OptionalFields or -HideFields." }

# The columns must exist on the table.
$attributes = @((Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Attributes?`$select=LogicalName").Content.value.LogicalName)
foreach ($field in @($ConditionField.ToLowerInvariant()) + $required + $hidden + $optional) { if ($field -notin $attributes) { throw "Column '$field' does not exist on $Table." } }
if (@((Invoke-DataverseRequest -Environment $dvEnv -Path "workflows?`$select=workflowid&`$filter=category eq 2 and primaryentity eq '$Table' and name eq '$(ConvertTo-ODataString $Name)'").Content.value).Count) { throw "A business rule '$Name' already exists on $Table." }

$id = ([guid]::NewGuid().ToString('N'))
$crm = '{0}, Microsoft.Crm.Workflow, Version=9.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'
$esc = [Security.SecurityElement]
$entityArg = '[InputEntities(&quot;primaryEntity&quot;)]'
$typeMap = @{
    OptionSetValue = @{ wf = 'OptionSetValue'; crmType = 'Picklist'; target = 'mxs:OptionSetValue' }
    String         = @{ wf = 'String'; crmType = 'String'; target = 'x:String' }
    Boolean        = @{ wf = 'Boolean'; crmType = 'Boolean'; target = 'x:Boolean' }
    Integer        = @{ wf = 'Integer'; crmType = 'Integer'; target = 'x:Int32' }
}[$ConditionType]
$literal = $esc::Escape($ConditionValue)

# The server reads DisplayNames back as "<Type>Step<n>: ..." to build the UiData: numbering is mandatory.
$script:step = 2
function Get-Actions([bool]$then) {
    $out = foreach ($f in $required) { $script:step++; "<Sequence DisplayName=`"SetFieldRequiredLevelStep$($script:step): $f`"><mcwc:SetFieldRequiredLevel ControlId=`"$f`" ControlType=`"standard`" Entity=`"$entityArg`" EntityName=`"$Table`" RequiredLevel=`"$(if ($then) { 'Required' } else { 'None' })`" /></Sequence>" }
    $out += foreach ($f in $optional) { $script:step++; "<Sequence DisplayName=`"SetFieldRequiredLevelStep$($script:step): $f`"><mcwc:SetFieldRequiredLevel ControlId=`"$f`" ControlType=`"standard`" Entity=`"$entityArg`" EntityName=`"$Table`" RequiredLevel=`"None`" /></Sequence>" }
    $out += foreach ($f in $hidden) { $script:step++; "<Sequence DisplayName=`"SetVisibilityStep$($script:step): $f`"><mcwc:SetVisibility ControlId=`"$f`" ControlType=`"standard`" Entity=`"$entityArg`" EntityName=`"$Table`" IsVisible=`"$(if ($then) { 'False' } else { 'True' })`" /></Sequence>" }
    return ($out -join '')
}
function Get-Composite([string]$key, [bool]$then) {
    "<mxswa:ActivityReference x:Key=`"$key`" AssemblyQualifiedName=`"$($crm -f 'Microsoft.Crm.Workflow.Activities.Composite')`" DisplayName=`"$(if ($then) { 'ConditionBranchStep2' } else { $script:step++; "ConditionBranchStep$($script:step)" })`"><mxswa:ActivityReference.Properties><sco:Collection x:TypeArguments=`"Variable`" x:Key=`"Variables`" /><sco:Collection x:TypeArguments=`"Activity`" x:Key=`"Activities`">$(Get-Actions $then)</sco:Collection></mxswa:ActivityReference.Properties></mxswa:ActivityReference>"
}

$xaml = @"
<Activity x:Class="XrmWorkflow$id" xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities" xmlns:mcwc="clr-namespace:Microsoft.Crm.Workflow.ClientActivities;assembly=Microsoft.Crm.Workflow, Version=9.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" xmlns:mva="clr-namespace:Microsoft.VisualBasic.Activities;assembly=System.Activities, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" xmlns:mxs="clr-namespace:Microsoft.Xrm.Sdk;assembly=Microsoft.Xrm.Sdk, Version=9.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" xmlns:mxsq="clr-namespace:Microsoft.Xrm.Sdk.Query;assembly=Microsoft.Xrm.Sdk, Version=9.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" xmlns:mxswa="clr-namespace:Microsoft.Xrm.Sdk.Workflow.Activities;assembly=Microsoft.Xrm.Sdk.Workflow, Version=9.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" xmlns:s="clr-namespace:System;assembly=mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" xmlns:scg="clr-namespace:System.Collections.Generic;assembly=mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" xmlns:sco="clr-namespace:System.Collections.ObjectModel;assembly=mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" xmlns:srs="clr-namespace:System.Runtime.Serialization;assembly=System.Runtime.Serialization, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" xmlns:this="clr-namespace:" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><x:Members><x:Property Name="InputEntities" Type="InArgument(scg:IDictionary(x:String, mxs:Entity))" /><x:Property Name="CreatedEntities" Type="InArgument(scg:IDictionary(x:String, mxs:Entity))" /></x:Members><this:XrmWorkflow$id.InputEntities><InArgument x:TypeArguments="scg:IDictionary(x:String, mxs:Entity)" /></this:XrmWorkflow$id.InputEntities><this:XrmWorkflow$id.CreatedEntities><InArgument x:TypeArguments="scg:IDictionary(x:String, mxs:Entity)" /></this:XrmWorkflow$id.CreatedEntities><mva:VisualBasic.Settings>Assembly references and imported namespaces for internal implementation</mva:VisualBasic.Settings><mxswa:Workflow><mxswa:ActivityReference AssemblyQualifiedName="$($crm -f 'Microsoft.Crm.Workflow.Activities.ConditionSequence')" DisplayName="ConditionStep1"><mxswa:ActivityReference.Arguments><InArgument x:TypeArguments="x:Boolean" x:Key="Wait">False</InArgument></mxswa:ActivityReference.Arguments><mxswa:ActivityReference.Properties><sco:Collection x:TypeArguments="Variable" x:Key="Variables"><Variable x:TypeArguments="x:Boolean" Default="False" Name="ConditionBranchStep2_condition" /><Variable x:TypeArguments="x:Object" Name="ConditionBranchStep2_1" /><Variable x:TypeArguments="x:Object" Name="ConditionBranchStep2_2" /></sco:Collection><sco:Collection x:TypeArguments="Activity" x:Key="Activities"><mxswa:GetEntityProperty Attribute="$($ConditionField.ToLowerInvariant())" Entity="$entityArg" EntityName="$Table" Value="[ConditionBranchStep2_1]"><mxswa:GetEntityProperty.TargetType><InArgument x:TypeArguments="s:Type"><mxswa:ReferenceLiteral x:TypeArguments="s:Type"><x:Null /></mxswa:ReferenceLiteral></InArgument></mxswa:GetEntityProperty.TargetType></mxswa:GetEntityProperty><mxswa:ActivityReference AssemblyQualifiedName="$($crm -f 'Microsoft.Crm.Workflow.Activities.EvaluateExpression')" DisplayName="EvaluateExpression"><mxswa:ActivityReference.Arguments><InArgument x:TypeArguments="x:String" x:Key="ExpressionOperator">CreateCrmType</InArgument><InArgument x:TypeArguments="s:Object[]" x:Key="Parameters">[New Object() { Microsoft.Xrm.Sdk.Workflow.WorkflowPropertyType.$($typeMap.wf), "$literal", "$($typeMap.crmType)" }]</InArgument><InArgument x:TypeArguments="s:Type" x:Key="TargetType"><mxswa:ReferenceLiteral x:TypeArguments="s:Type" Value="$($typeMap.target)" /></InArgument><OutArgument x:TypeArguments="x:Object" x:Key="Result">[ConditionBranchStep2_2]</OutArgument></mxswa:ActivityReference.Arguments></mxswa:ActivityReference><mxswa:ActivityReference AssemblyQualifiedName="$($crm -f 'Microsoft.Crm.Workflow.Activities.EvaluateCondition')" DisplayName="EvaluateCondition"><mxswa:ActivityReference.Arguments><InArgument x:TypeArguments="mxsq:ConditionOperator" x:Key="ConditionOperator">$ConditionOperator</InArgument><InArgument x:TypeArguments="s:Object[]" x:Key="Parameters">[New Object() { ConditionBranchStep2_2 }]</InArgument><InArgument x:TypeArguments="x:Object" x:Key="Operand">[ConditionBranchStep2_1]</InArgument><OutArgument x:TypeArguments="x:Boolean" x:Key="Result">[ConditionBranchStep2_condition]</OutArgument></mxswa:ActivityReference.Arguments></mxswa:ActivityReference><mxswa:ActivityReference AssemblyQualifiedName="$($crm -f 'Microsoft.Crm.Workflow.Activities.ConditionBranch')" DisplayName="ConditionBranchStep2"><mxswa:ActivityReference.Arguments><InArgument x:TypeArguments="x:Boolean" x:Key="Condition">[ConditionBranchStep2_condition]</InArgument></mxswa:ActivityReference.Arguments><mxswa:ActivityReference.Properties>$(Get-Composite 'Then' $true)<x:Null x:Key="Else" /><x:String x:Key="Description">$($esc::Escape($Name))</x:String></mxswa:ActivityReference.Properties></mxswa:ActivityReference></sco:Collection><x:Boolean x:Key="ContainsElseBranch">False</x:Boolean></mxswa:ActivityReference.Properties></mxswa:ActivityReference></mxswa:Workflow></Activity>
"@.Trim()
[void][xml]$xaml   # well-formed XML

$body = [ordered]@{
    name = $Name; category = 2; type = 1; scope = 4; primaryentity = $Table
    ondemand = $false; subprocess = $false; triggeroncreate = $false; mode = 0; xaml = $xaml
    # Without processtriggerscope, activation generates no processtrigger (load / change): the rule never runs
    # on the form (found by Playwright, CRM-413). 1 = all forms.
    processtriggerscope = 1
}
if ($Description) { $body.description = $Description }

if ($DryRun) {
    [ordered]@{ dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; table = $Table; rule = $Name
        condition = "$ConditionField $ConditionOperator $ConditionValue ($ConditionType)"; require = $required; optional = $optional; hide = $hidden; xamlLength = $xaml.Length } | ConvertTo-Json
    return
}

$workflowId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'workflows' -Body $body -SolutionUniqueName $solutionInfo.uniqueName).EntityId
$state = 'draft'
try {
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "workflows($workflowId)" -Body @{ statecode = 1; statuscode = 2 } | Out-Null
    $state = 'active'
}
catch { Write-Warning "Rule created but not activated: $($_.Exception.Message)" }
$status = Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $workflowId -ComponentType Workflow
$check = (Invoke-DataverseRequest -Environment $dvEnv -Path "workflows($workflowId)?`$select=statecode,clientdata").Content
$triggers = @((Invoke-DataverseRequest -Environment $dvEnv -Path "processtriggers?`$select=event,controlname&`$filter=_processid_value eq $workflowId").Content.value | ForEach-Object { ($_.event, $_.controlname | Where-Object { $_ }) -join ' ' })
if ($state -eq 'active' -and -not ($triggers -match "^change $($ConditionField.ToLowerInvariant())$")) { Write-Warning "No change trigger on ${ConditionField}: the rule will not run on the form."; $state = 'active-without-trigger' }

$components = @(New-AlchemistComponent -Type Workflow -Id $workflowId -Name "$Table / $Name" -Status $status)
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.businessrule.create' -Details @{
    environment = $dvEnv.name; table = $Table; rule = $Name; workflowId = $workflowId; state = $state; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ created = $true; rule = $Name; workflowId = $workflowId; state = $state; clientCodeGenerated = [bool]$check.clientdata; triggers = $triggers; components = $components } | ConvertTo-Json -Depth 4
if ($state -ne 'active') { exit 1 }


