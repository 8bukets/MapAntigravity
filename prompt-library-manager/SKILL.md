# Prompt Library Manager

## Description
This skill provides the agent with the capability to manage, parse, and add new prompts to the Prompt Library application.

## Usage
The Prompt Library data is stored in `prompts.json` in the root of the repository, but the source of truth is `raw_prompts.txt`.

The agent can use the scripts in the `scripts/` directory to manage the library:
- `parse_prompts.py`: Parses the `raw_prompts.txt` file and generates `prompts.json`.
- `add_prompt.py`: A helper script to programmatically append new prompts to `raw_prompts.txt` and automatically run `parse_prompts.py`.

## Schema
The `prompts.json` file contains an array of prompt objects with the following schema:
- `category` (string): The category of the prompt.
- `title` (string): The title of the prompt.
- `text` (string): The actual prompt template text, which may contain variables in brackets, e.g., `[VARIABLE]`.
- `variables` (array of strings): A list of the variables extracted from the text.
