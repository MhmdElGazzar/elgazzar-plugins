# Reads a User Story from Azure DevOps (read-only) and prints it as JSON:
# title, description, acceptance criteria, area, iteration, and related work items.
#
# Needs these environment variables:
#   AZDO_ORG_URL  e.g. https://dev.azure.com/my-org
#   AZDO_PROJECT  e.g. MyProject
#   AZDO_PAT      Personal Access Token with "Work Items (Read)" scope
#
# Usage: powershell -ExecutionPolicy Bypass -File get_story.ps1 -Id 1234
param(
    [Parameter(Mandatory = $true)][int]$Id
)
$ErrorActionPreference = 'Stop'

foreach ($name in 'AZDO_ORG_URL', 'AZDO_PROJECT', 'AZDO_PAT') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing environment variable: $name" }
}
$org = $env:AZDO_ORG_URL.TrimEnd('/')
$project = [Uri]::EscapeDataString($env:AZDO_PROJECT)
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)"))
$headers = @{ Authorization = "Basic $auth" }

function Get-WorkItem([int]$WorkItemId, [switch]$WithRelations) {
    $expand = if ($WithRelations) { '&$expand=relations' } else { '' }
    Invoke-RestMethod -Headers $headers -Uri "$org/$project/_apis/wit/workitems/$WorkItemId`?api-version=7.1$expand"
}

# Strips HTML tags so the text is readable.
function ConvertTo-PlainText([string]$Html) {
    if (-not $Html) { return '' }
    $text = $Html -replace '<br\s*/?>|</p>|</li>|</div>', "`n" -replace '<[^>]+>', ''
    [System.Net.WebUtility]::HtmlDecode($text).Trim()
}

$item = Get-WorkItem -WorkItemId $Id -WithRelations
$f = $item.fields

$related = @()
foreach ($rel in $item.relations) {
    if ($rel.url -notmatch '/workItems/(\d+)$') { continue }   # skip attachments and hyperlinks
    $relId = [int]$Matches[1]
    $relItem = Get-WorkItem -WorkItemId $relId
    $related += [ordered]@{
        id       = $relId
        relation = $rel.attributes.name
        type     = $relItem.fields.'System.WorkItemType'
        title    = $relItem.fields.'System.Title'
        state    = $relItem.fields.'System.State'
    }
}

[ordered]@{
    id                 = $item.id
    type               = $f.'System.WorkItemType'
    title              = $f.'System.Title'
    state              = $f.'System.State'
    areaPath           = $f.'System.AreaPath'
    iterationPath      = $f.'System.IterationPath'
    description        = ConvertTo-PlainText $f.'System.Description'
    acceptanceCriteria = ConvertTo-PlainText $f.'Microsoft.VSTS.Common.AcceptanceCriteria'
    url                = "$org/$project/_workitems/edit/$($item.id)"
    related            = $related
} | ConvertTo-Json -Depth 5
