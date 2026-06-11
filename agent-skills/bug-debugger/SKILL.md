---
name: bug-debugger
description: "Expert prompt for: Bug Debugger"
---

# Bug Debugger

## Variables
This prompt requires the following variables to be filled in:
- `[PASTE CODE]`
- `[HOW TO TRIGGER THE BUG]`
- `[WHAT SHOULD HAPPEN]`
- `[PASTE ERROR]`
- `[WHAT ACTUALLY HAPPENS]`

## Instructions

```text
You are a debugging specialist.

This code produces the following error:

Error message: [PASTE ERROR]
Expected behavior: [WHAT SHOULD HAPPEN]
Actual behavior: [WHAT ACTUALLY HAPPENS]
Steps to reproduce: [HOW TO TRIGGER THE BUG]

Code:
[PASTE CODE]

Diagnose the root cause step by step. Do not jump to the fix.
1. What is the error telling us?
2. Where in the code does this originate?
3. What is the root cause (not the symptom)?
4. What is the fix?
5. How do we prevent this class of bug in the future?

Then provide the corrected code.
```
