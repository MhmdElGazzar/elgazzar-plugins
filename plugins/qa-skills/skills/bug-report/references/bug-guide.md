# Bug Reporting Guide

Read this file while writing a bug. It explains how to set the severity and priority, how to
classify the bug, how to check for duplicates, and the order of the scripts.

## Contents
1. Severity
2. Priority
3. Front-end or Back-end
4. Title rules
5. Evidence
6. Checking for duplicates
7. Azure workflow (scripts order)

---

## 1. Severity

Severity is the impact of the bug on the system. Choose it from the evidence, not from how urgent
it feels.

| Severity | Azure value | When | Examples |
|---|---|---|---|
| Critical | 1 - Critical | The system crashes, data is lost or wrong, security is broken, or the main flow is blocked with no workaround | Login fails for all users; transfer deducts money twice; a user sees another user's data |
| High | 2 - High | A major feature is broken, but the rest of the system works | Transfer accepts amounts above the limit; report export fails |
| Medium | 3 - Medium | A feature works partly, or there is a workaround | Search ignores one filter; wrong validation message |
| Low | 4 - Low | Cosmetic, with no effect on the function | Misaligned label; extra space; wrong icon color |

## 2. Priority

Priority is how soon the bug should be fixed.

| Priority | Azure value | When |
|---|---|---|
| High | 1 | Must be fixed before the release, or it blocks testing |
| Medium | 2 | Should be fixed in the current sprint |
| Low | 3 | Can wait for a later sprint |

Priority usually follows severity, but not always:
- A Low-severity typo on the login page can be High priority, because every user sees it.
- A High-severity bug in a rarely used admin report can be Medium priority.

## 3. Front-end or Back-end

Use the evidence to decide. When an API response is available, it settles the question.

| Type | Category | Signs |
|---|---|---|
| Front-end | Functional | The API returns the right data, but the screen behaves wrongly: wrong validation, button does nothing, wrong navigation, wrong calculation on the screen |
| Front-end | UI | The screen looks wrong: layout, alignment, RTL direction, wrong text or label, missing translation, not matching Figma |
| Back-end | API | The API returns wrong data, a wrong status code (4xx/5xx), or an error message |
| Back-end | Integration | The problem is between systems: external service, data sync, email/SMS notification, scheduled job |

How to check:
1. Open the browser developer tools (F12), then the Network tab.
2. Repeat the action, and look at the API request and response.
3. If the response is correct but the screen is wrong, it's Front-end. If the response is wrong,
   it's Back-end.

If you can't tell, say so in the bug and ask the user for the API response.

## 4. Title rules

Format: `[Environment][Role] What is wrong + where`

A good title answers four questions: where (environment), who (role), what is wrong, and when.

| ❌ Bad | ✅ Good |
|---|---|
| "Transfer not working" | "[Staging][Customer] Transfer above 10,000 EGP succeeds without an error message" |
| "Bug in users" | "[UAT][Admin] GET /api/users returns 500 when the search contains Arabic letters" |
| "Arabic issue" | "[Staging][Customer] Transfer screen shows English labels when the language is Arabic" |

## 5. Evidence

| Bug type | Best evidence |
|---|---|
| UI | Screenshot, with the wrong area highlighted. Add the Figma design to compare |
| Functional (several steps) | Video of the whole flow |
| API | The request (URL, method, body) and the full response (status code and body) |
| Integration | Logs with the time of the action, plus the request ID if there is one |

Every bug has at least a screenshot or a video. Remove passwords, tokens, and personal data from
screenshots and logs before attaching them.

## 6. Checking for duplicates

Before creating a bug, run `scripts/find_bugs.ps1`:
- with keywords from the title (feature name, screen, field, API)
- with the story ID
- inside the module (`-AreaPath`)

Then:
- **Same problem, bug is open:** don't create a new bug. Show the existing one to the user, and
  suggest adding a comment with the new evidence.
- **Same problem, bug is closed:** the bug came back. Suggest reopening it, or create a new bug
  that links to the old one.
- **Similar but different:** create the new bug, and mention the similar one.

## 7. Azure workflow (scripts order)

All scripts need `AZDO_ORG_URL`, `AZDO_PROJECT` and `AZDO_PAT`.

1. Write the bug and show it to the user for review.
2. `find_bugs.ps1`: check for duplicates.
3. After approval, write the bug to a JSON file (see `assets/bug_template.json`).
4. `create_bug.ps1 -File bugs.json -DryRun`: preview what will be created.
5. `create_bug.ps1 -File bugs.json`: create the bug, upload the evidence, and link it.
6. At the end of the test run: `execution_summary.ps1 -PlanId <id>` for the summary.
