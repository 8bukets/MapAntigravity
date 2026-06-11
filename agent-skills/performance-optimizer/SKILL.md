---
name: performance-optimizer
description: "Expert prompt for: Performance Optimizer"
---

# Performance Optimizer

## Variables
This prompt requires the following variables to be filled in:
- `[PASTE CODE]`
- `[WHAT THE CODE DOES AND WHERE IT RUNS]`

## Instructions

```text
You are a performance engineer.

Analyze this code/page for performance issues.

Context: [WHAT THE CODE DOES AND WHERE IT RUNS]

Code:
[PASTE CODE]

Identify:
1. What is slow and why (be specific — measure, don't guess)
2. Quick wins (changes that take under 30 minutes and have immediate impact)
3. Medium-term improvements (changes that require some refactoring)
4. Architecture-level optimizations (if applicable)

For each optimization:
- Current code
- Optimized code
- Expected improvement (estimate)

Prioritize by effort-to-impact ratio.
```
