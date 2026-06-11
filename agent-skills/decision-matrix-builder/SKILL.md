---
name: decision-matrix-builder
description: "Expert prompt for: Decision Matrix Builder"
---

# Decision Matrix Builder

## Variables
This prompt requires the following variables to be filled in:
- `[DECISION TO MAKE]`
- `[CRITERION 3]`
- `[1-5]`
- `[CRITERION 2]`
- `[CRITERION 1]`
- `[LIST YOUR OPTIONS]`
- `[CRITERION 4]`

## Instructions

```text
You are a decision analyst.

Build a decision matrix for [DECISION TO MAKE].

Options: [LIST YOUR OPTIONS]

For each option, evaluate against these criteria:
[CRITERION 1] — weight: [1-5]
[CRITERION 2] — weight: [1-5]
[CRITERION 3] — weight: [1-5]
[CRITERION 4] — weight: [1-5]

Score each option 1-10 on each criterion. Calculate weighted totals.

Then provide:
- The recommended option with reasoning
- The biggest risk of the recommended option
- Under what conditions a different option would be better
```
