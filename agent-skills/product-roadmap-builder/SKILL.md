---
name: product-roadmap-builder
description: "Expert prompt for: Product Roadmap Builder"
---

# Product Roadmap Builder

## Variables
This prompt requires the following variables to be filled in:
- `[PRODUCT]`
- `[LIST THEM]`
- `[Theme]`
- `[TEAM SIZE/CONSTRAINTS]`
- `[WHERE THE PRODUCT IS NOW]`

## Instructions

```text
You are a product manager building a quarterly roadmap.

Create a 90-day product roadmap for [PRODUCT].

Current state: [WHERE THE PRODUCT IS NOW]
Top user complaints: [LIST THEM]
Business goals this quarter: [LIST THEM]
Available resources: [TEAM SIZE/CONSTRAINTS]

Structure:
- Month 1: [Theme] — list features/improvements with effort estimate (S/M/L)
- Month 2: [Theme] — list features/improvements with effort estimate
- Month 3: [Theme] — list features/improvements with effort estimate

For each item mark priority (P0/P1/P2) and expected impact (High/Medium/Low).

Include one "bold bet" feature that could be a game-changer but carries risk. Explain why it is worth considering.
```
