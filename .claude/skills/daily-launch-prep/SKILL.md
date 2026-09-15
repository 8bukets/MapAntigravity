---
name: daily-launch-prep
description: Daily autonomous pass over this repo's shell/Python tooling to keep it correct and safe. Runs unattended once a day via a scheduled Routine.
---

# Daily Launch Prep — MapAntigravity

You are running unattended, once a day, with no memory of previous runs
beyond what is committed in this repository. `LAUNCH_CHECKLIST.md` at the
repo root is your memory — read it first, update it every run.

## What this repo is

A prompt-library/agent-skills manager: shell scripts that auto-resolve
GitHub PRs and GitLab MRs (`auto_resolve_prs.sh`,
`auto_resolve_mrs_gitlab.sh`), plus `agent-skills/` (62+ generated skill
directories) and `export_to_skills.py` which generates them from
`prompts.json`. Internal tooling — no "Product/business" category here.

## Hard guardrails — never cross these

1. **Never merge your own PRs, never push to the default branch
   directly.**
2. **Be extra careful with `auto_resolve_prs.sh` and
   `auto_resolve_mrs_gitlab.sh`** — these scripts can merge OTHER people's
   PRs/MRs automatically. A 2026-09-14 audit found and fixed a real bug
   where malformed CI-status API responses made the script fail *open*
   (treat unverified CI as "success" and proceed to merge) due to a bash
   `errexit`-suppression quirk inside an `if` condition. Any change to
   these scripts' CI-status-checking logic needs to be proven to fail
   *closed* (skip/block the merge) on malformed input, not just to work
   on the happy path.
3. **Never commit secrets.**

## Each run, in order

1. **Orient**: `git log --oneline -10` and read `LAUNCH_CHECKLIST.md`.
2. **Validate**: `bash -n` on every `.sh` file, `python3 -m py_compile`
   on every `.py` file, run `test_resolution.sh` if present, and run
   `validate_skill.py` against all `agent-skills/*` directories.
3. **Targeted review**: re-read `auto_resolve_prs.sh` and
   `auto_resolve_mrs_gitlab.sh` for the same class of bug already found
   once (unquoted variables causing word-splitting on paths with spaces;
   `set -e`/`errexit` being silently suppressed inside conditions,
   masking a real failure as success). Also check `export_to_skills.py`
   for unescaped characters when generating YAML frontmatter from prompt
   titles (a latent bug — unescaped `"`/`\` — was already fixed once;
   confirm no new prompt titles reintroduce it after regenerating from
   `prompts.json`).
4. **Update `LAUNCH_CHECKLIST.md`** with today's date.
5. **Ship it**: only for a real, reproduced bug — branch
   `daily-launch-prep/YYYY-MM-DD`, commit (include a minimal repro of
   the bug in the commit message, the way the 2026-09-14 fixes did),
   push, open a PR via direct REST API
   (`https://api.github.com/repos/8bukets/MapAntigravity/pulls`, base
   `main`). End the PR body with
   `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
6. **If there's nothing actionable, say so plainly** rather than forcing
   a change.

## Launch readiness categories (track in LAUNCH_CHECKLIST.md)

- **Reliability**: shell scripts pass `bash -n`, Python passes
  `py_compile`, `agent-skills/*` all pass `validate_skill.py`.
- **Security**: the auto-merge scripts must fail closed on any
  malformed/unexpected CI-status API response, never fail open.
