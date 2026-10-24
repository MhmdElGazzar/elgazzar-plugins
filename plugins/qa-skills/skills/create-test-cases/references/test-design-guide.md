# Test Design Guide

Read this file while designing the test cases. It explains how to find the scenarios, how to write
each test case, and how to pick the regression test cases.

## Contents
1. Test design techniques
2. Coverage checklist
3. Writing rules
4. Smoke vs Regression
5. Priority rules
6. Finding regression test cases
7. Azure workflow (scripts order)

---

## 1. Test design techniques

Pick the technique that fits the rule in the story.

| Technique | Use it when | How |
|---|---|---|
| Equivalence partitioning | A field accepts a range or a type of values | Split the values into valid and invalid groups, and test one value from each group |
| Boundary values | A rule has a min or a max | Test min-1, min, max, max+1 (e.g. 0, 1, 10,000, 10,001) |
| Decision table | Several conditions combine to give different results | List each combination that gives a different result, and test each one |
| State transition | The item has statuses (e.g. Draft → Pending → Approved) | Test every allowed transition, and the important forbidden ones |
| Error guessing | Always, at the end | Special characters, very long text, spaces only, double click, refresh mid-flow, session timeout |

## 2. Coverage checklist

For every AC and business rule, check which of these apply:

- **Positive**: the main flow works with valid data.
- **Negative**: invalid input or action is rejected, with the right message.
- **Boundary**: the exact limits and one step outside them.
- **Validation**: mandatory fields, length, format, allowed characters.
- **Permissions**: each role sees and does only what it should.
- **Language & layout**: the Arabic and English texts are correct, and the Arabic screen is RTL.
- **Figma**: the screen matches the design (fields, labels, order, buttons).

Skip the items that don't apply. Every AC must have at least one test case.

## 3. Writing rules

**Title**: `Verify` + what + condition.
- ✅ "Verify transfer is rejected above the maximum amount"
- ❌ "Transfer test 2"

**Preconditions**: everything that must be true before the first action (logged-in role, existing
data, settings). In Azure Test Plans, they go in step 1.

**Steps**: one action per step, using the real names of screens, fields and buttons.

**Test data**: real values. When testing a boundary, write the exact boundary value.

**Expected result**: what the tester can see or check:
- The exact message in both languages: `EN: "..." / AR: "..."`
- What changes on the screen
- What is saved, or not saved

Copy the texts from the story or the design. Don't translate them yourself.

## 4. Smoke vs Regression

| Tag | What goes in it | When it runs |
|---|---|---|
| Smoke | Only the main happy paths that prove the feature works | After every build. Keep it small and fast |
| Regression | Test cases that protect existing behavior | Before a release |

- A test case can have both tags. The main happy path is usually Smoke and Regression.
- Negative, boundary and validation test cases are Regression, not Smoke.

## 5. Priority rules

| Priority | Azure value | Use for |
|---|---|---|
| High | 1 | Main flows, money, data loss, security and permissions |
| Medium | 2 | Important negative cases and validations, alternative flows |
| Low | 3 | Cosmetic issues and rare cases |

## 6. Finding regression test cases

A feature is impacted when the story changes something it uses: the same screen, data, rule, API,
report or notification.

1. List the impacted features from the story (and from the requirement analysis, if there is one).
2. Search Azure Test Plans with `scripts/find_test_cases.ps1`:
   - by the related stories: `-StoryIds`
   - by keywords from the feature names: `-Keywords`
   - inside the module: `-AreaPath`
3. Read the titles, and keep only the test cases that really cover an impacted behavior.
4. Reuse them as they are. Write a new regression test case only for an impacted behavior that no
   existing test case covers.
5. If a new test case would cover the same thing as an existing one, reuse the existing one instead.

## 7. Azure workflow (scripts order)

All scripts need `AZDO_ORG_URL`, `AZDO_PROJECT` and `AZDO_PAT`.

1. `get_story.ps1 -Id <story>`: read the story, its AC, and its related items.
2. `find_test_cases.ps1`: find existing test cases for regression and to avoid duplicates.
3. Design the test cases and show them to the user for review.
4. After approval, write them to a JSON file (see `assets/test_cases_template.json`).
5. `create_test_case.ps1 ... -DryRun`: preview what will be created.
6. `create_test_case.ps1 ...`: create them, link them to the story, and add them to the suite.
