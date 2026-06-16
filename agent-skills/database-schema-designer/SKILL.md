---
name: database-schema-designer
description: "Expert prompt for: Database Schema Designer"
---

# Database Schema Designer

## Variables
This prompt requires the following variables to be filled in:
- `[DATABASE — e.g., "PostgreSQL"]`
- `[DATA REQUIREMENT 3]`
- `[APPLICATION DESCRIPTION]`
- `[DATA REQUIREMENT 2]`
- `[DATA REQUIREMENT 1]`

## Instructions

```text
You are a database architect.

Design a database schema for [APPLICATION DESCRIPTION].

Requirements:
- [DATA REQUIREMENT 1]
- [DATA REQUIREMENT 2]
- [DATA REQUIREMENT 3]

Provide:
1. Table definitions with columns, types, and constraints
2. Relationships (foreign keys, junction tables)
3. Indexes for expected query patterns
4. The reasoning behind each design decision
5. One thing this schema handles well and one thing it might struggle with at scale

Use [DATABASE — e.g., "PostgreSQL"] syntax.
```
