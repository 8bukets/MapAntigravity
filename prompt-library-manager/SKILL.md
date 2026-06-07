# Prompt Library Manager

## Description
This skill provides the agent with the capability to manage, parse, and add new prompts to the Prompt Library application.

## Usage
The Prompt Library data is stored in `prompts.json` in the root of the repository.

The agent can use the scripts in the `scripts/` directory to manage the library:
- `parse_prompts.py`: Analyzes the `prompts.json` file.
- `add_prompt.py`: A helper script to programmatically append new prompts to `prompts.json`.

## Schema
The `prompts.json` file contains an array of prompt objects with the following schema:
- `category` (string): The category of the prompt.
- `title` (string): The title of the prompt.
- `text` (string): The actual prompt template text, which may contain variables in brackets, e.g., `[VARIABLE]`.
- `variables` (array of strings): A list of the variables extracted from the text.
