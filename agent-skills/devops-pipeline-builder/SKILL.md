---
name: devops-pipeline-builder
description: "Expert prompt for: DevOps Pipeline Builder"
---

# DevOps Pipeline Builder

## Variables
This prompt requires the following variables to be filled in:
- `[PLATFORM — e.g., "GitHub"]`
- `[WHERE — e.g., "Vercel", "AWS", "Railway"]`
- `[APPLICATION]`
- `[YOUR STACK]`

## Instructions

```text
You are a DevOps engineer building a CI/CD pipeline.

Create a deployment pipeline for [APPLICATION].

Stack: [YOUR STACK]
Hosting: [WHERE — e.g., "Vercel", "AWS", "Railway"]
Repository: [PLATFORM — e.g., "GitHub"]

Provide:
1. GitHub Actions workflow file (or equivalent)
2. Environment variable management strategy
3. Testing stage configuration
4. Deployment stage configuration
5. Rollback procedure
6. Monitoring and alerting recommendations

Include the actual YAML/config files, not just descriptions.
```
