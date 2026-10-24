# Builds the test execution summary from Azure Test Plans (read-only).
# Reads the latest outcome of every test case in a test plan (or one suite), finds the bugs linked
# to those test cases, and prints the summary as JSON:
#   counts (total, executed, passed, failed, blocked, not run), pass rate,
#   bugs by severity and by type, the bug list, and the blocked test cases with their linked bugs.
#
# Needs these environment variables:
#   AZDO_ORG_URL, AZDO_PROJECT, and AZDO_PAT (with "Test Management (Read)" and "Work Items (Read)")
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File execution_summary.ps1 -PlanId 50
#   powershell -ExecutionPolicy Bypass -File execution_summary.ps1 -PlanId 50 -SuiteId 51
param(
    [Parameter(Mandatory = $true)][int]$PlanId,
    [int]$SuiteId
)
$ErrorActionPreference = 'Stop'

foreach ($name in 'AZDO_ORG_URL', 'AZDO_PROJECT', 'AZDO_PAT') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing environment variable: $name" }
}
$org = $env:AZDO_ORG_URL.TrimEnd('/')
$project = [Uri]::EscapeDataString($env:AZDO_PROJECT)
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)"))
$headers = @{ Authorization = "Basic $auth"; 'Content-Type' = 'application/json' }

# GET that follows Azure's continuation token, and returns all items.
function Get-AllPages([string]$Path) {
    $items = @()
    $token = $null
    do {
        $uri = "$org/$project/_apis/$Path"
        if ($token) { $uri += "&continuationToken=$([Uri]::EscapeDataString($token))" }
        $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $uri
        $json = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()) | ConvertFrom-Json
        $items += @($json.value)
        $token = $response.Headers['x-ms-continuationtoken']
    } while ($token)
    $items
}

function Get-WorkItems([int[]]$Ids, [string[]]$Fields, [switch]$WithRelations) {
    $all = @()
    for ($i = 0; $i -lt $Ids.Count; $i += 200) {
        $chunk = $Ids[$i..([Math]::Min($i + 199, $Ids.Count - 1))]
        $body = @{ ids = $chunk }
        if ($WithRelations) { $body.'$expand' = 'Relations' } else { $body.fields = $Fields }
        $json = ConvertTo-Json -InputObject $body -Depth 5
        $all += @((Invoke-RestMethod -Method POST -Headers $headers -Uri "$org/$project/_apis/wit/workitemsbatch?api-version=7.1" -Body ([Text.Encoding]::UTF8.GetBytes($json))).value)
    }
    $all
}

# Maps an Azure outcome to the summary buckets.
function Get-Bucket([string]$Outcome) {
    switch ($Outcome) {
        'passed'        { 'Passed' }
        'failed'        { 'Failed' }
        'blocked'       { 'Blocked' }
        'notApplicable' { 'NotApplicable' }
        default         { 'NotRun' }    # none, unspecified, notExecuted, inProgress, paused, ...
    }
}

# 1. Test points (one per test case per suite) with their latest outcome
$suiteIds = if ($SuiteId) { @($SuiteId) } else { @(Get-AllPages "testplan/Plans/$PlanId/suites?api-version=7.1" | ForEach-Object { $_.id }) }
$points = @()
foreach ($sid in $suiteIds) {
    $points += @(Get-AllPages "testplan/Plans/$PlanId/Suites/$sid/TestPoint?api-version=7.1")
}

$counts = [ordered]@{ total = 0; executed = 0; passed = 0; failed = 0; blocked = 0; notRun = 0; notApplicable = 0 }
$blockedOrFailed = @{}   # test case id -> bucket
foreach ($p in $points) {
    $bucket = Get-Bucket $p.results.outcome
    switch ($bucket) {
        'Passed'        { $counts.passed++ }
        'Failed'        { $counts.failed++ }
        'Blocked'       { $counts.blocked++ }
        'NotApplicable' { $counts.notApplicable++ }
        'NotRun'        { $counts.notRun++ }
    }
    if ($bucket -in 'Failed', 'Blocked') { $blockedOrFailed[[int]$p.testCaseReference.id] = $bucket }
}
$counts.executed = $counts.passed + $counts.failed + $counts.blocked
$counts.total = $counts.executed + $counts.notRun          # not applicable is reported, not counted
$passRate = if ($counts.executed) { [Math]::Round(100 * $counts.passed / $counts.executed, 1) } else { 0 }

# 2. Bugs linked to the failed and blocked test cases (a test case "Tests" a bug)
$bugIds = New-Object System.Collections.Generic.List[int]
$bugsOfTestCase = @{}
if ($blockedOrFailed.Count) {
    foreach ($tc in (Get-WorkItems -Ids ([int[]]@($blockedOrFailed.Keys)) -WithRelations)) {
        $bugsOfTestCase[[int]$tc.id] = @()
        foreach ($rel in $tc.relations) {
            if ($rel.rel -ne 'Microsoft.VSTS.Common.TestedBy-Reverse' -or $rel.url -notmatch '/workItems/(\d+)$') { continue }
            $bugsOfTestCase[[int]$tc.id] += [int]$Matches[1]
            if (-not $bugIds.Contains([int]$Matches[1])) { $bugIds.Add([int]$Matches[1]) }
        }
    }
}

$bugs = @()
if ($bugIds.Count) {
    $fields = 'System.Id', 'System.WorkItemType', 'System.Title', 'System.State', 'System.Tags', 'Microsoft.VSTS.Common.Severity'
    foreach ($wi in (Get-WorkItems -Ids $bugIds.ToArray() -Fields $fields)) {
        if ($wi.fields.'System.WorkItemType' -ne 'Bug') { continue }
        $bugs += [pscustomobject][ordered]@{
            id       = $wi.id
            title    = $wi.fields.'System.Title'
            severity = ($wi.fields.'Microsoft.VSTS.Common.Severity' -replace '^\d+\s*-\s*', '')
            state    = $wi.fields.'System.State'
            tags     = $wi.fields.'System.Tags'
        }
    }
}

# 3. Group the bugs by severity and by type (type comes from the tags set by create_bug.ps1)
$bySeverity = [ordered]@{ Critical = 0; High = 0; Medium = 0; Low = 0 }
$byType = [ordered]@{ 'Front-end Functional' = 0; 'Front-end UI' = 0; 'Back-end API' = 0; 'Back-end Integration' = 0; 'Unclassified' = 0 }
foreach ($b in $bugs) {
    if ($bySeverity.Contains($b.severity)) { $bySeverity[$b.severity]++ }
    $tags = @(($b.tags -split ';') | ForEach-Object { $_.Trim() })
    $layer = @('Front-end', 'Back-end') | Where-Object { $tags -contains $_ } | Select-Object -First 1
    $category = @('Functional', 'UI', 'API', 'Integration') | Where-Object { $tags -contains $_ } | Select-Object -First 1
    $key = "$layer $category"
    if ($layer -and $category -and $byType.Contains($key)) { $byType[$key]++ } else { $byType['Unclassified']++ }
}

# 4. Blocked test cases, with the bugs that block them (the reason, when recorded)
$blocked = @()
foreach ($tcId in $blockedOrFailed.Keys) {
    if ($blockedOrFailed[$tcId] -ne 'Blocked') { continue }
    $linked = @($bugsOfTestCase[$tcId])
    $blocked += [ordered]@{
        testCaseId = $tcId
        blockedBy  = if ($linked.Count) { ($linked | ForEach-Object { "#$_" }) -join ', ' } else { 'No linked bug - ask the user for the reason' }
    }
}

[ordered]@{
    planId     = $PlanId
    suiteIds   = $suiteIds
    counts     = $counts
    passRate   = "$passRate%"
    bySeverity = $bySeverity
    byType     = $byType
    bugs       = $bugs
    blocked    = $blocked
} | ConvertTo-Json -Depth 5
