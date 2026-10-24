# QA Skills

Three Claude Code skills that cover a QA engineer's work on a User Story, from the first read to the
last bug. They are built for teams that use Azure DevOps, Azure Test Plans and Figma, on an
application that supports Arabic and English.

| Skill | What it does | Output |
|---|---|---|
| `requirement-analysis` | Reviews a User Story or BRD: business rules, acceptance criteria, gaps, impact, and conflicts with related stories. Gives a readiness verdict. | Word file with the questions for the BA/PO, each linked to its story |
| `create-test-cases` | Designs test cases that cover every AC and business rule, with Arabic and English expected results, Figma screenshots, and Smoke/Regression tags. Reuses existing regression test cases. | Test cases in Azure Test Plans, linked to the story, after approval |
| `bug-report` | Writes reproducible bugs with a clear title, evidence, severity, priority, and Front-end/Back-end classification. Checks for duplicates. | Bugs in Azure DevOps, linked to the test case and story, plus a test execution summary |

Nothing is created in Azure DevOps before the user reviews and approves it.

## Install

```
claude plugin marketplace add MhmdElGazzar/elgazzar-plugins
claude plugin install qa-skills@elgazzar-plugins
```

## Setup

The scripts run in Windows PowerShell and talk to Azure DevOps through its REST API. Set these
environment variables:

| Variable | Example |
|---|---|
| `AZDO_ORG_URL` | `https://dev.azure.com/my-org` |
| `AZDO_PROJECT` | `MyProject` |
| `AZDO_PAT` | A Personal Access Token with Work Items (Read & Write) and Test Management (Read & Write) |

Without them, the skills still work in chat; they just can't read from or write to Azure DevOps.

`requirement-analysis` creates the Word file through Microsoft Word, so Word must be installed.

## Use

Just talk to Claude:
- "Analyze this story" (paste the story, or give its ID)
- "Create test cases for story 1234"
- "This test case failed, log a bug" (with a screenshot or video)
- "Give me the execution summary for test plan 50"

## Status

The skill instructions and the offline parts of the scripts are tested. The Azure DevOps calls are
not tested against a live organization yet.
