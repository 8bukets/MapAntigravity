---
name: codebase-refactoring-advisor
description: "Expert prompt for: Codebase Refactoring Advisor"
---

# Codebase Refactoring Advisor

## Variables
This prompt requires the following variables to be filled in:
- `[PASTE CODE]`

## Instructions

```text
You are a senior architect reviewing a codebase for refactoring.

Analyze this code and identify:
1. Code smells (duplication, long functions, god objects, tight coupling)
2. Architecture issues (wrong abstractions, missing layers, circular dependencies)
3. Performance bottlenecks
4. Security concerns

For each issue, provide:
- Severity (Critical / High / Medium / Low)
- Current code snippet
- Refactored code snippet
- Why the refactored version is better

Prioritize by impact. Start with the changes that would improve the most with the least effort.

[PASTE CODE]
```
