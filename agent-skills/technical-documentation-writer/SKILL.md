---
name: technical-documentation-writer
description: "Expert prompt for: Technical Documentation Writer"
---

# Technical Documentation Writer

## Variables
This prompt requires the following variables to be filled in:
- `[PASTE CODE OR API SPEC]`
- `[PROJECT/API/LIBRARY]`

## Instructions

```text
You are a technical writer creating documentation for developers.

Write documentation for [PROJECT/API/LIBRARY].

Code/API reference:
[PASTE CODE OR API SPEC]

Include:
1. Overview (what it does, who it is for, when to use it)
2. Quick start (get running in under 5 minutes)
3. API reference (every public method with parameters, return types, examples)
4. Common use cases (3-5 real-world examples with code)
5. Troubleshooting (top 5 issues and their fixes)

Write for a developer who is competent but has never seen this project before. Assume nothing.
```
