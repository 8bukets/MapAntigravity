---
name: test-suite-generator
description: "Expert prompt for: Test Suite Generator"
---

# Test Suite Generator

## Variables
This prompt requires the following variables to be filled in:
- `[TESTING FRAMEWORK — e.g., "Jest", "pytest"]`
- `[FUNCTION/COMPONENT/MODULE]`
- `[PASTE CODE]`

## Instructions

```text
You are a QA engineer who writes comprehensive test suites.

Write tests for [FUNCTION/COMPONENT/MODULE].

Code to test:
[PASTE CODE]

Include:
1. Unit tests for every public function
2. Edge cases (null inputs, empty arrays, boundary values, invalid types)
3. Integration tests for any external dependencies
4. At least one test that verifies error handling works correctly

Use [TESTING FRAMEWORK — e.g., "Jest", "pytest"].
Each test should have a clear, descriptive name that explains what it verifies.
```
