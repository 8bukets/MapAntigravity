# MapAntigravity - Autonomous PR Resolution & Prompt Management

This repository features an autonomous system for managing GitHub Pull Requests and continuously improving AI prompts.

## Features

- **Autonomous PR Conflict Resolution**: Automatically detects conflicts in open PRs and uses the Gemini CLI to resolve them, ensuring branches stay synced with the target.
- **WIP/HOLD Detection**: Automatically skips PRs marked with "WIP", "HOLD", or specific hold labels to avoid premature merges.
- **Proactive Merging**: Automatically merges the base branch into PR branches to keep them up to date.
- **Continuous Prompt Improvement**: An autonomous agent that evaluates and improves a library of prompts based on LLM-generated feedback.
- **Automated Workflow**: Scheduled execution every 4 hours via GitHub Actions to ensure continuous maintenance.

## Components

### 1. `auto_resolve_prs.sh`
The core shell script that:
1. Fetches all open PRs.
2. Identifies PRs with conflicts or those that are behind the base branch.
3. Performs a local merge and uses Gemini CLI to resolve any file-level conflicts.
4. Pushes the resolved changes back to the PR branch.
5. Performs a squash-merge if the PR is mergeable and up to date.

### 2. `autonomous_agent.py`
A Python script that:
1. Loads prompts from `prompts.json`.
2. Generates dummy variables for testing.
3. Invokes Gemini CLI to generate a response and evaluate it.
4. If the score is low, uses Gemini CLI to improve the prompt.
5. Saves the improved prompts back to the library.

### 3. `GEMINI.md`
Provides persistent global context and role-specific instructions for the Gemini CLI agent when operating in this repository.

## Setup

### Prerequisites
- Node.js & npm
- [Gemini CLI](https://github.com/google/gemini-cli): `npm install -g @google/gemini-cli`
- `jq`
- `curl`

### GitHub Secrets
The following secrets are required in your GitHub repository:
- `GITHUB_TOKEN`: A token with `contents: write`, `pull-requests: write`, and `issues: write` permissions.
- `GEMINI_API_KEY`: Your API key for the Gemini API.

## Workflow
The system is configured to run automatically every 4 hours via `.github/workflows/auto-resolve-pr.yml`. You can also trigger it manually from the "Actions" tab.
