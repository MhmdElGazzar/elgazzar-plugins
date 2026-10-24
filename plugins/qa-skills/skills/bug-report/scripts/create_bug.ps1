# Creates approved bugs in Azure DevOps. This WRITES to Azure DevOps, so run it only after the user
# approves the bugs. Run with -DryRun first to preview what will be created.
#
# For each bug it:
#   - creates a Bug work item (title, repro steps, severity, priority, tags, system info)
#   - uploads the screenshot, video, logs, or API request/response as attachments
#   - links it to the failed test case ("Tested By") and the User Story ("Related")
#   - puts it in the same area and iteration as the User Story
#
# Needs these environment variables:
#   AZDO_ORG_URL, AZDO_PROJECT, and AZDO_PAT (with "Work Items (Read & Write)" scope)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File create_bug.ps1 -File bugs.json -DryRun
#   powershell -ExecutionPolicy Bypass -File create_bug.ps1 -File bugs.json
#
# bugs.json is a list of bugs (UTF-8). See assets/bug_template.json for the format.
param(
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

foreach ($name in 'AZDO_ORG_URL', 'AZDO_PROJECT', 'AZDO_PAT') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing environment variable: $name" }
}
$org = $env:AZDO_ORG_URL.TrimEnd('/')
$project = [Uri]::EscapeDataString($env:AZDO_PROJECT)
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)"))

function Invoke-AzDo([string]$Method, [string]$Path, $Body, [string]$ContentType = 'application/json') {
    $params = @{ Method = $Method; Uri = "$org/$project/_apis/$Path"; Headers = @{ Authorization = "Basic $auth" }; ContentType = $ContentType }
    if ($Body -is [byte[]]) { $params.Body = $Body }
    elseif ($null -ne $Body) { $params.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 10)) }
    Invoke-RestMethod @params
}

function ConvertTo-Html([string]$Text) {
    if (-not $Text) { return '' }
    [System.Net.WebUtility]::HtmlEncode($Text) -replace "`r?`n", '<br/>'
}

# Builds the Repro Steps field: preconditions, test data, steps, expected and actual result.
function ConvertTo-ReproSteps($Bug) {
    $steps = (@($Bug.steps) | ForEach-Object { "<li>$(ConvertTo-Html $_)</li>" }) -join ''
    "<b>Preconditions:</b><br/>$(ConvertTo-Html $Bug.preconditions)<br/><br/>" +
    "<b>Test Data:</b><br/>$(ConvertTo-Html $Bug.testData)<br/><br/>" +
    "<b>Steps to Reproduce:</b><ol>$steps</ol>" +
    "<b>Expected Result:</b><br/>$(ConvertTo-Html $Bug.expected)<br/><br/>" +
    "<b>Actual Result:</b><br/>$(ConvertTo-Html $Bug.actual)"
}

$severityMap = @{ 'Critical' = '1 - Critical'; 'High' = '2 - High'; 'Medium' = '3 - Medium'; 'Low' = '4 - Low' }
$priorityMap = @{ 'High' = 1; 'Medium' = 2; 'Low' = 3 }
$typeMap = @{ 'Front-end' = @('Functional', 'UI'); 'Back-end' = @('API', 'Integration') }

# Assign first, then wrap: in Windows PowerShell 5.1, @(... | ConvertFrom-Json) nests the whole array as one item.
$parsed = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
$bugs = @($parsed)

# Validate everything before writing anything, so a bad file never creates half the bugs.
foreach ($bug in $bugs) {
    $label = if ($bug.title) { "'$($bug.title)'" } else { '(no title)' }
    foreach ($field in 'title', 'severity', 'priority', 'layer', 'category', 'environment', 'role', 'expected', 'actual', 'storyId') {
        if (-not $bug.$field) { throw "Bug $label is missing '$field'." }
    }
    if (-not $bug.steps) { throw "Bug $label has no steps." }
    if (-not $severityMap.ContainsKey([string]$bug.severity)) { throw "Bug $label`: severity must be Critical, High, Medium or Low." }
    if (-not $priorityMap.ContainsKey([string]$bug.priority)) { throw "Bug $label`: priority must be High, Medium or Low." }
    if (-not $typeMap.ContainsKey([string]$bug.layer)) { throw "Bug $label`: layer must be Front-end or Back-end." }
    if ($typeMap[[string]$bug.layer] -notcontains [string]$bug.category) {
        throw "Bug $label`: category for $($bug.layer) must be $($typeMap[[string]$bug.layer] -join ' or ')."
    }
    if (-not $bug.attachments) { throw "Bug $label needs at least a screenshot or a video." }
    foreach ($path in @($bug.attachments)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Bug $label`: attachment not found: $path" }
    }
}

if ($DryRun) {
    'DRY RUN - nothing will be created.'
    foreach ($bug in $bugs) {
        "  BUG: $($bug.title)"
        "       Severity: $($bug.severity) | Priority: $($bug.priority) | Type: $($bug.layer), $($bug.category)"
        "       Story: #$($bug.storyId) | Test case: $(if ($bug.testCaseId) { "#$($bug.testCaseId)" } else { 'none' }) | Attachments: $(@($bug.attachments).Count)"
    }
    return
}

$created = @()
foreach ($bug in $bugs) {
    $story = Invoke-AzDo GET "wit/workitems/$($bug.storyId)`?api-version=7.1"
    $systemInfo = "<b>Environment:</b> $(ConvertTo-Html $bug.environment)<br/><b>Role:</b> $(ConvertTo-Html $bug.role)"

    $patch = @(
        @{ op = 'add'; path = '/fields/System.Title'; value = $bug.title }
        @{ op = 'add'; path = '/fields/Microsoft.VSTS.TCM.ReproSteps'; value = (ConvertTo-ReproSteps $bug) }
        @{ op = 'add'; path = '/fields/Microsoft.VSTS.TCM.SystemInfo'; value = $systemInfo }
        @{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Severity'; value = $severityMap[[string]$bug.severity] }
        @{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Priority'; value = $priorityMap[[string]$bug.priority] }
        @{ op = 'add'; path = '/fields/System.Tags'; value = "$($bug.layer); $($bug.category)" }
        @{ op = 'add'; path = '/fields/System.AreaPath'; value = $story.fields.'System.AreaPath' }
        @{ op = 'add'; path = '/fields/System.IterationPath'; value = $story.fields.'System.IterationPath' }
        @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'System.LinkTypes.Related'; url = "$org/_apis/wit/workItems/$($bug.storyId)" } }
    )
    if ($bug.testCaseId) {
        $patch += @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'Microsoft.VSTS.Common.TestedBy-Forward'; url = "$org/_apis/wit/workItems/$($bug.testCaseId)" } }
    }

    foreach ($path in @($bug.attachments)) {
        $fileName = [Uri]::EscapeDataString((Split-Path -Leaf $path))
        $upload = Invoke-AzDo POST "wit/attachments?fileName=$fileName&api-version=7.1" ([IO.File]::ReadAllBytes($path)) 'application/octet-stream'
        $patch += @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'AttachedFile'; url = $upload.url } }
    }

    $wi = Invoke-AzDo POST 'wit/workitems/$Bug?api-version=7.1' $patch 'application/json-patch+json'
    $created += [ordered]@{ id = $wi.id; title = $bug.title; url = "$org/$project/_workitems/edit/$($wi.id)" }
}

ConvertTo-Json -InputObject @($created) -Depth 5
