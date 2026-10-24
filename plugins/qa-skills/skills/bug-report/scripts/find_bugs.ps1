# Finds existing Bugs in Azure DevOps (read-only), to avoid logging the same bug twice.
# Prints them as JSON: id, title, state, severity, priority, tags, area, assigned to, and link.
#
# Search by any mix of:
#   -StoryIds       bugs already linked to these stories
#   -Keywords       bugs whose title contains any of these words
#   -AreaPath       limit the keyword search to a module (area path and everything under it)
#   -IncludeClosed  also return Closed and Done bugs (by default only open bugs are returned)
#
# Needs these environment variables:
#   AZDO_ORG_URL  e.g. https://dev.azure.com/my-org
#   AZDO_PROJECT  e.g. MyProject
#   AZDO_PAT      Personal Access Token with "Work Items (Read)" scope
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File find_bugs.ps1 -Keywords transfer,limit -AreaPath "MyProject\Payments"
#   powershell -ExecutionPolicy Bypass -File find_bugs.ps1 -StoryIds 1234
param(
    [int[]]$StoryIds = @(),
    [string[]]$Keywords = @(),
    [string]$AreaPath,
    [switch]$IncludeClosed,
    [int]$Top = 50
)
$ErrorActionPreference = 'Stop'

if (-not $StoryIds -and -not $Keywords) { throw 'Pass -StoryIds and/or -Keywords.' }
foreach ($name in 'AZDO_ORG_URL', 'AZDO_PROJECT', 'AZDO_PAT') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing environment variable: $name" }
}
$org = $env:AZDO_ORG_URL.TrimEnd('/')
$project = [Uri]::EscapeDataString($env:AZDO_PROJECT)
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)"))
$headers = @{ Authorization = "Basic $auth"; 'Content-Type' = 'application/json' }

function Invoke-AzDo([string]$Method, [string]$Path, $Body) {
    $params = @{ Method = $Method; Headers = $headers; Uri = "$org/$project/_apis/$Path" }
    if ($Body) { $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5)) }
    Invoke-RestMethod @params
}

$ids = New-Object System.Collections.Generic.List[int]

# 1. Work items linked to the given stories (kept only if they are Bugs, in step 3)
foreach ($storyId in $StoryIds) {
    $story = Invoke-AzDo GET "wit/workitems/$storyId`?`$expand=relations&api-version=7.1"
    foreach ($rel in $story.relations) {
        if ($rel.url -notmatch '/workItems/(\d+)$') { continue }
        $linkedId = [int]$Matches[1]
        if (-not $ids.Contains($linkedId)) { $ids.Add($linkedId) }
    }
}

# 2. Bugs whose title matches the keywords
if ($Keywords) {
    $titleFilter = ($Keywords | ForEach-Object { "[System.Title] CONTAINS '$($_ -replace "'", "''")'" }) -join ' OR '
    $wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project " +
            "AND [System.WorkItemType] = 'Bug' AND ($titleFilter)"
    if ($AreaPath) { $wiql += " AND [System.AreaPath] UNDER '$($AreaPath -replace "'", "''")'" }
    if (-not $IncludeClosed) { $wiql += " AND [System.State] NOT IN ('Closed', 'Done', 'Removed')" }
    $wiql += ' ORDER BY [System.ChangedDate] DESC'
    $result = Invoke-AzDo POST "wit/wiql?`$top=$Top&api-version=7.1" @{ query = $wiql }
    foreach ($wi in $result.workItems) { if (-not $ids.Contains([int]$wi.id)) { $ids.Add([int]$wi.id) } }
}

if ($ids.Count -eq 0) { '[]'; return }

# 3. Read the details, and keep only Bugs (the batch API takes up to 200 ids per call)
$fields = 'System.Id', 'System.WorkItemType', 'System.Title', 'System.State', 'System.Tags', 'System.AreaPath',
          'System.AssignedTo', 'Microsoft.VSTS.Common.Severity', 'Microsoft.VSTS.Common.Priority'
$closedStates = 'Closed', 'Done', 'Removed'
$found = @()
for ($i = 0; $i -lt $ids.Count; $i += 200) {
    $chunk = $ids.GetRange($i, [Math]::Min(200, $ids.Count - $i))
    $batch = Invoke-AzDo POST 'wit/workitemsbatch?api-version=7.1' @{ ids = $chunk; fields = $fields }
    foreach ($wi in $batch.value) {
        if ($wi.fields.'System.WorkItemType' -ne 'Bug') { continue }
        if (-not $IncludeClosed -and $closedStates -contains $wi.fields.'System.State') { continue }
        $found += [ordered]@{
            id         = $wi.id
            title      = $wi.fields.'System.Title'
            state      = $wi.fields.'System.State'
            severity   = $wi.fields.'Microsoft.VSTS.Common.Severity'
            priority   = $wi.fields.'Microsoft.VSTS.Common.Priority'
            tags       = $wi.fields.'System.Tags'
            areaPath   = $wi.fields.'System.AreaPath'
            assignedTo = $wi.fields.'System.AssignedTo'.displayName
            url        = "$org/$project/_workitems/edit/$($wi.id)"
        }
    }
}

ConvertTo-Json -InputObject @($found | Select-Object -First $Top) -Depth 5
