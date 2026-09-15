# Launch Readiness Checklist — MapAntigravity

Living document, updated by the `daily-launch-prep` skill on each scheduled
run. Newest entries at the top of each section.

## Reliability

### Done
- 2026-09-14: Fixed word-splitting bug in `auto_resolve_mrs_gitlab.sh`
  (`for file in $conflicts` unquoted) that silently skipped resolving
  conflicts on any file path containing a space — switched to the
  `while read` pattern already used correctly in the sibling script.
- 2026-09-14: Fixed unescaped quotes/backslashes in `export_to_skills.py`
  when a prompt title contains `"` or `\`, which produced invalid YAML
  frontmatter in generated `SKILL.md` files. Latent bug (no current
  prompt triggers it) — closed off.
- Verified: `test_resolution.sh` harness and `validate_skill.py` against
  all 62 `agent-skills/*` directories pass.

## Security

### Done
- 2026-09-14: **Fixed a fail-open bug in `auto_resolve_prs.sh`'s
  `check_ci_status()`.** A malformed/empty GitHub check-runs API response
  (404, secondary rate limit, etc.) crashed the internal `jq` filter;
  because of a bash `errexit`-suppression quirk when a command runs as
  an `if` condition, the failure was silently swallowed and the script
  fell through to reporting "CI SUCCESS" — meaning it could have
  squash-merged a PR whose CI status was never actually verified. Fixed
  to validate `.check_runs` is an array up front and fail closed
  otherwise.

---
_This checklist was seeded on 2026-09-15 based on the 2026-09-13/14
session's findings; it is not itself an autonomous run's output._
