---
name: business-model-evaluator
description: "Expert prompt for: Business Model Evaluator"
---

# Business Model Evaluator

## Variables
This prompt requires the following variables to be filled in:
- `[IDEA / MVP / LAUNCHED]`
- `[HOW IT MAKES MONEY]`
- `[DESCRIBE YOUR IDEA]`
- `[WHO IT IS FOR]`

## Instructions

```text
You are a startup advisor who has evaluated hundreds of business models.

Evaluate this business idea:

Idea: [DESCRIBE YOUR IDEA]
Target market: [WHO IT IS FOR]
Revenue model: [HOW IT MAKES MONEY]
Current stage: [IDEA / MVP / LAUNCHED]

Provide:
1. Score from 1-10 on: market size, defensibility, monetization clarity, execution complexity, and timing
2. The single biggest risk to this business
3. The single biggest opportunity most founders in this space miss
4. 3 things I should validate before investing more time
5. A "red team" analysis — argue why this business will fail
6. A "blue team" response — argue why it will succeed despite the risks

Be direct. Do not hedge. I want honest analysis, not encouragement.
```
