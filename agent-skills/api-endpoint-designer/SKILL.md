---
name: api-endpoint-designer
description: "Expert prompt for: API Endpoint Designer"
---

# API Endpoint Designer

## Variables
This prompt requires the following variables to be filled in:
- `[FEATURE/APPLICATION]`
- `[LANGUAGE/FRAMEWORK]`

## Instructions

```text
You are a backend engineer designing a REST API.

Design the API endpoints for [FEATURE/APPLICATION].

For each endpoint provide:
- Method and path
- Request body (if applicable)
- Response format (JSON)
- Authentication requirements
- Error responses (400, 401, 403, 404, 500)
- Rate limiting recommendations

Then implement the top 3 most important endpoints in [LANGUAGE/FRAMEWORK].

Include input validation and error handling.
```
