# Creates approved test cases in Azure Test Plans. This WRITES to Azure DevOps, so run it only after
# the user approves the test cases. Run with -DryRun first to preview what will be created.
#
# For each test case it:
#   - creates a Test Case work item (title, steps, priority, tags, test data)
#   - puts the preconditions as step 1
#   - links it to the User Story ("Tests")
#   - attaches the Figma screenshot, if one is given
#   - adds it to the test suite
# It also adds existing (reused) regression test cases to the same suite, without changing them.
#
# Needs the same environment variables as get_story.ps1: AZDO_ORG_URL, AZDO_PROJECT, AZDO_PAT
# (the PAT needs "Work Items (Read & Write)" and "Test Management (Read & Write)").
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File create_test_case.ps1 -File test_cases.json -StoryId 1234 -PlanId 50 -SuiteId 51 -DryRun
#   powershell -ExecutionPolicy Bypass -File create_test_case.ps1 -File test_cases.json -StoryId 1234 -PlanId 50 -SuiteId 51 -ExistingIds 845,912
#
# test_cases.json format (UTF-8), see assets/test_cases_template.json:
# [
#   {
#     "title": "Verify transfer is rejected above the maximum amount",
#     "priority": "High",
#     "tags": ["Regression"],
#     "preconditions": "User is logged in, and the balance is 20,000 EGP",
#     "testData": "amount = 10,001",
#     "attachment": "C:\\path\\to\\figma.png",
#     "steps": [ { "action": "Open the Transfer screen", "expected": "The Transfer screen opens" } ]
#   }
# ]
param(
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][int]$StoryId,
    [Parameter(Mandatory = $true)][int]$PlanId,
    [Parameter(Mandatory = $true)][int]$SuiteId,
    [int[]]$ExistingIds = @(),
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

# Turns plain text into the HTML that Azure shows inside a step (keeps line breaks).
function ConvertTo-StepHtml([string]$Text) {
    if (-not $Text) { return '' }
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text) -replace "`r?`n", '<BR/>'
    "<DIV><P>$encoded</P></DIV>"
}

# Builds the Microsoft.VSTS.TCM.Steps XML. Step 1 holds the preconditions.
function ConvertTo-StepsXml($TestCase) {
    $all = @()
    if ($TestCase.preconditions) { $all += [pscustomobject]@{ action = "Preconditions: $($TestCase.preconditions)"; expected = '' } }
    $all += @($TestCase.steps)
    $xml = New-Object System.Text.StringBuilder
    [void]$xml.Append("<steps id=`"0`" last=`"$($all.Count)`">")
    for ($i = 0; $i -lt $all.Count; $i++) {
        $type = if ($all[$i].expected) { 'ValidateStep' } else { 'ActionStep' }
        $action = [System.Security.SecurityElement]::Escape((ConvertTo-StepHtml $all[$i].action))
        $expected = [System.Security.SecurityElement]::Escape((ConvertTo-StepHtml $all[$i].expected))
        [void]$xml.Append("<step id=`"$($i + 1)`" type=`"$type`">")
        [void]$xml.Append("<parameterizedString isformatted=`"true`">$action</parameterizedString>")
        [void]$xml.Append("<parameterizedString isformatted=`"true`">$expected</parameterizedString>")
        [void]$xml.Append('<description/></step>')
    }
    [void]$xml.Append('</steps>')
    $xml.ToString()
}

$priorityMap = @{ 'High' = 1; 'Medium' = 2; 'Low' = 3 }
# Assign first, then wrap: in Windows PowerShell 5.1, @(... | ConvertFrom-Json) nests the whole array as one item.
$parsed = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
$testCases = @($parsed)

# Validate everything before writing anything, so a bad file never creates half the test cases.
foreach ($tc in $testCases) {
    if (-not $tc.title) { throw 'Every test case needs a title.' }
    if (-not $tc.steps) { throw "Test case '$($tc.title)' has no steps." }
    if ($tc.priority -and -not $priorityMap.ContainsKey([string]$tc.priority)) { throw "Test case '$($tc.title)': priority must be High, Medium or Low." }
    if ($tc.attachment -and -not (Test-Path -LiteralPath $tc.attachment)) { throw "Attachment not found: $($tc.attachment)" }
}

# New test cases go to the same area and iteration as the story.
$story = Invoke-AzDo GET "wit/workitems/$StoryId`?api-version=7.1"
$storyUrl = "$org/_apis/wit/workItems/$StoryId"

if ($DryRun) {
    "DRY RUN - nothing will be created."
    "Story: #$StoryId $($story.fields.'System.Title')"
    "Plan $PlanId / Suite $SuiteId"
    foreach ($tc in $testCases) {
        $tags = @($tc.tags) -join ', '
        "  NEW: [$($tc.priority)] $($tc.title) | Tags: $tags | Steps: $(@($tc.steps).Count) + preconditions"
    }
    foreach ($id in $ExistingIds) { "  REUSE: #$id (added to the suite as is)" }
    return
}

$created = @()
foreach ($tc in $testCases) {
    $patch = @(
        @{ op = 'add'; path = '/fields/System.Title'; value = $tc.title }
        @{ op = 'add'; path = '/fields/Microsoft.VSTS.TCM.Steps'; value = (ConvertTo-StepsXml $tc) }
        @{ op = 'add'; path = '/fields/System.AreaPath'; value = $story.fields.'System.AreaPath' }
        @{ op = 'add'; path = '/fields/System.IterationPath'; value = $story.fields.'System.IterationPath' }
        @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'Microsoft.VSTS.Common.TestedBy-Reverse'; url = $storyUrl } }
    )
    if ($tc.priority) { $patch += @{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Priority'; value = $priorityMap[[string]$tc.priority] } }
    if ($tc.tags) { $patch += @{ op = 'add'; path = '/fields/System.Tags'; value = (@($tc.tags) -join '; ') } }
    if ($tc.testData) { $patch += @{ op = 'add'; path = '/fields/System.Description'; value = "<b>Test Data:</b><br/>$(ConvertTo-StepHtml $tc.testData)" } }

    if ($tc.attachment) {
        $fileName = [Uri]::EscapeDataString((Split-Path -Leaf $tc.attachment))
        $upload = Invoke-AzDo POST "wit/attachments?fileName=$fileName&api-version=7.1" ([IO.File]::ReadAllBytes($tc.attachment)) 'application/octet-stream'
        $patch += @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'AttachedFile'; url = $upload.url; attributes = @{ comment = 'Figma design' } } }
    }

    $wi = Invoke-AzDo POST 'wit/workitems/$Test%20Case?api-version=7.1' $patch 'application/json-patch+json'
    $created += [ordered]@{ id = $wi.id; title = $tc.title; url = "$org/$project/_workitems/edit/$($wi.id)" }
}

# Add the new and the reused test cases to the suite.
$suiteIds = @($created | ForEach-Object { $_.id }) + $ExistingIds
if ($suiteIds.Count -gt 0) {
    $body = @($suiteIds | ForEach-Object { @{ workItem = @{ id = $_ } } })
    [void](Invoke-AzDo POST "testplan/Plans/$PlanId/Suites/$SuiteId/TestCase?api-version=7.1" $body)
}

[ordered]@{
    story   = "#$StoryId $($story.fields.'System.Title')"
    suite   = "Plan $PlanId / Suite $SuiteId"
    created = $created
    reused  = $ExistingIds
} | ConvertTo-Json -Depth 5
