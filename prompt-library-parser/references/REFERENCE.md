# Raw Prompts Format

The raw prompt files (typically `raw_prompts.txt`) follow a structured text format that allows categorization, title extraction, and variable identification.

## Structure

The file is divided into categories using `Part X: Category Name` headers. Within each category, prompts are listed using `Prompt Y — Title` headers followed by the prompt text.

### Category Header
```text
Part 1: Content Creation (Prompts 1–10)
```
- Must start with `Part `
- Followed by a number and a colon `:`
- The text after the colon is captured as the category name.

### Prompt Header
```text
Prompt 1 — Blog Post Outline Generator
```
- Must start with `Prompt `
- Followed by a number and an em dash `—` (or standard dash if supported by the regex)
- The text after the dash is captured as the prompt title.

### Prompt Text
The text immediately following the Prompt Header up to the next Prompt Header or Category Header is the prompt text.
Variables within the prompt text are enclosed in square brackets, e.g., `[Topic]`, `[Target Audience]`. The parser automatically extracts these for UI generation.

## Example File
```text
Part 1: Content Creation (Prompts 1–10)

Prompt 1 — Blog Post Outline Generator
You are an expert content strategist. Create a comprehensive blog post outline on the topic of [Topic]. The target audience is [Target Audience]. Include an engaging introduction, 3-5 main sections with bullet points, and a compelling conclusion.
```