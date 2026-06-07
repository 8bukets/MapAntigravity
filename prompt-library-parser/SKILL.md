---
name: prompt-library-parser
description: Parses raw text prompts from a text file into a structured JSON file. Use when you need to update the prompt library, regenerate the prompts.json file, or when working with prompt library updates.
license: MIT
compatibility: Requires python3 and the standard library
metadata:
  author: AI Agent
  version: "1.0"
---

# Prompt Library Parser Skill

This skill allows agents to parse the raw text prompts found in the repository into a structured `prompts.json` format required by the Prompt Library web application.

## When to use

Use this skill when:
- The user asks to regenerate `prompts.json`
- New prompts have been added to the raw text format and need to be built into the JSON format
- The application needs the latest structured prompts

## Instructions

The main logic is implemented in a Python script located at `scripts/parse_prompts.py`.

### Step-by-step Execution

1. Verify that the raw prompt text file exists (typically `raw_prompts.txt` in the root).
2. Run the extraction script:
   ```bash
   python3 scripts/parse_prompts.py <path_to_raw_prompts.txt> <path_to_output.json>
   ```
   Example:
   ```bash
   python3 prompt-library-parser/scripts/parse_prompts.py raw_prompts.txt prompts.json
   ```
3. Verify the output file was successfully created.

### Common edge cases
- If the output file already exists, it will be overwritten.
- Make sure to use relative paths appropriately depending on where you execute the script from.
