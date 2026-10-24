# Analysis Checklist

Use this file during the analysis. It lists what to look for in each step, so nothing important is
missed.

## Contents
1. Gaps checklist
2. Acceptance criteria checks
3. Impact areas
4. Conflict types
5. Priority and severity rules
6. Readiness verdict rules

---

## 1. Gaps checklist

For each item, ask: "Does the story say what happens here?" If it doesn't, and the answer would
change how the feature is tested, it's a gap. Skip items that clearly don't apply.

**Data & fields**
- Mandatory vs optional fields, and default values
- Min/max length, allowed characters, format (email, phone, ID), Arabic and English input
- Numbers: min/max, decimals, negative values, zero, rounding
- Dates: format, timezone, past or future allowed
- Duplicates: what happens if the same value is entered twice

**Behavior**
- The error message for each invalid case, and where it appears
- Cancel, back or refresh in the middle of the flow
- Double submit, and two users editing the same record
- Empty states: no data, no search results
- Statuses: which ones exist, and which transitions are allowed

**Users & permissions**
- Which roles can view, create, edit or delete
- What an unauthorized user sees

**Integrations**
- External systems or APIs, and what happens when they fail or time out
- Notifications (email, SMS): content, receiver, and timing

**Non-functional**
- Performance expectations
- Audit and logging
- Localization: Arabic/English, RTL, date and number formats
- Supported browsers and devices

## 2. Acceptance criteria checks

An AC is good when it is:
- **Specific**: no vague words like "fast", "user-friendly", "properly", "etc."
- **Testable**: it has a clear, observable expected result.
- **Complete**: it states the condition, the action, and the result (ideally Given/When/Then).
- **Single**: one behavior per AC.
- **Consistent**: it doesn't contradict another AC or the description.

## 3. Impact areas

| Area | What to check |
|---|---|
| Screens / UI | Existing pages, forms or menus that change |
| Business rules | Existing rules or calculations that are modified |
| Data | New or changed fields and statuses, effect on existing data, migration |
| APIs & integrations | APIs or external systems that send or receive the changed data |
| Roles & permissions | Roles that gain, lose or change access |
| Reports & notifications | Reports, exports, emails or SMS that use the affected data |
| Other modules | Features that share the same data or flow |

Impact types: **New**, **Modified**, **Removed**, **Indirect** (not changed directly, but affected).

## 4. Conflict types

| Type | Meaning | Example |
|---|---|---|
| Contradiction | The same rule is defined differently | Story A: max 10,000. Story B: max 5,000 |
| Overlap | Two stories build the same thing | Both stories add an "Export to Excel" button |
| Dependency | The story needs another story to be done first | Payment story needs the Wallet story |
| Behavior change | The story breaks an AC of an older story | Old story: delete is allowed. New story: only archive |
| Scope gap | Something falls between two stories | Neither story covers editing after approval |
| Inconsistency | Different names or messages for the same thing | "Client" in one story, "Customer" in another |

If a conflict is likely but not certain, mark it as **Needs confirmation**.

## 5. Priority and severity rules

**Questions**
- **High**: testing can't be done without the answer.
- **Medium**: affects some test cases.
- **Low**: clarification only.

**Conflicts and impact**
- **High**: affects money, data, security, permissions, or a core flow.
- **Medium**: affects a secondary flow or validation.
- **Low**: cosmetic or wording only.

## 6. Readiness verdict rules

- **Ready**: no High questions and no conflicts.
- **Ready with questions**: there are open questions, but none blocks testing of the main flow.
- **Not ready**: any unresolved High conflict, the main flow is unclear, or there are no acceptance
  criteria.
