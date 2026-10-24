# Finds existing Test Cases in Azure DevOps (read-only), to reuse them for regression and to avoid
# duplicates. Prints them as JSON: id, title, state, priority, tags, area, and the stories they test.
#
# Search by any mix of:
#   -StoryIds  test cases already linked ("Tested By") to these stories
#   -Keywords  test cases whose title contains any of these words
#   -AreaPath  limit the keyword search to a module (area path and everything under it)
#
# Needs the same environment variables as get_story.ps1: AZDO_ORG_URL, AZDO_PROJECT, AZDO_PAT.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File find_test_cases.ps1 -StoryIds 1234,1180
#   powershell -ExecutionPolicy Bypass -File find_test_cases.ps1 -Keywords transfer,statement -AreaPath "MyProject\Payments"
param(
    [int[]]$StoryIds = @(),
    [string[]]$Keywords = @(),
    [string]$AreaPath,
    [int]$Top = 100
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

# Test case id -> list of story ids it tests
$testedStories = @{}
$ids = New-Object System.Collections.Generic.List[int]

# 1. Test cases linked to the given stories
foreach ($storyId in $StoryIds) {
    $story = Invoke-AzDo GET "wit/workitems/$storyId`?`$expand=relations&api-version=7.1"
    foreach ($rel in $story.relations) {
        if ($rel.rel -ne 'Microsoft.VSTS.Common.TestedBy-Forward') { continue }
        if ($rel.url -notmatch '/workItems/(\d+)$') { continue }
        $tcId = [int]$Matches[1]
        if (-not $testedStories.ContainsKey($tcId)) { $testedStories[$tcId] = @(); $ids.Add($tcId) }
        $testedStories[$tcId] += $storyId
    }
}

# 2. Test cases whose title matches the keywords
if ($Keywords) {
    $titleFilter = ($Keywords | ForEach-Object { "[System.Title] CONTAINS '$($_ -replace "'", "''")'" }) -join ' OR '
    $wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project " +
            "AND [System.WorkItemType] = 'Test Case' AND ($titleFilter)"
    if ($AreaPath) { $wiql += " AND [System.AreaPath] UNDER '$($AreaPath -replace "'", "''")'" }
    $result = Invoke-AzDo POST "wit/wiql?`$top=$Top&api-version=7.1" @{ query = $wiql }
    foreach ($wi in $result.workItems) { if (-not $ids.Contains([int]$wi.id)) { $ids.Add([int]$wi.id) } }
}

if ($ids.Count -eq 0) { '[]'; return }

# 3. Read the details of all found test cases (the batch API takes up to 200 ids per call)
$fields = 'System.Id', 'System.Title', 'System.State', 'System.Tags', 'System.AreaPath', 'Microsoft.VSTS.Common.Priority'
$found = @()
for ($i = 0; $i -lt [Math]::Min($ids.Count, $Top); $i += 200) {
    $chunk = $ids.GetRange($i, [Math]::Min(200, [Math]::Min($ids.Count, $Top) - $i))
    $batch = Invoke-AzDo POST 'wit/workitemsbatch?api-version=7.1' @{ ids = $chunk; fields = $fields }
    foreach ($wi in $batch.value) {
        $found += [ordered]@{
            id       = $wi.id
            title    = $wi.fields.'System.Title'
            state    = $wi.fields.'System.State'
            priority = $wi.fields.'Microsoft.VSTS.Common.Priority'
            tags     = $wi.fields.'System.Tags'
            areaPath = $wi.fields.'System.AreaPath'
            tests    = if ($testedStories.ContainsKey([int]$wi.id)) { $testedStories[[int]$wi.id] } else { @() }
            url      = "$org/$project/_workitems/edit/$($wi.id)"
        }
    }
}

ConvertTo-Json -InputObject @($found) -Depth 5
