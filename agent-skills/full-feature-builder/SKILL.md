---
name: full-feature-builder
description: "Expert prompt for: Full Feature Builder"
---

# Full Feature Builder

## Variables
This prompt requires the following variables to be filled in:
- `[REQUIREMENT 1]`
- `[CONSTRAINT — e.g., "Must work on mobile"]`
- `[CONSTRAINT — e.g., "Under 200ms response time"]`
- `[BRIEF DESCRIPTION]`
- `[FEATURE DESCRIPTION]`
- `[YOUR STACK — e.g., "Next.js, TypeScript, Supabase, Tailwind"]`
- `[REQUIREMENT 2]`
- `[REQUIREMENT 3]`

## Instructions

```text
You are a senior full-stack developer.

Build [FEATURE DESCRIPTION] for my application.

Tech stack: [YOUR STACK — e.g., "Next.js, TypeScript, Supabase, Tailwind"]
Current architecture: [BRIEF DESCRIPTION]

Requirements:
- [REQUIREMENT 1]
- [REQUIREMENT 2]
- [REQUIREMENT 3]

Constraints:
- [CONSTRAINT — e.g., "Must work on mobile"]
- [CONSTRAINT — e.g., "Under 200ms response time"]

Before writing any code, outline your approach in 5 steps.
Then implement each step with clean, production-ready code.
Include error handling and edge cases.
Add inline comments only where the logic is non-obvious.
```
