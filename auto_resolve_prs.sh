#!/bin/bash
# auto_resolve_prs.sh

set -euo pipefail

# Helper function for logging with timestamps
log() {
  printf "[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

# Global variables for cleanup
ALL_PRS_FILE=""
PR_LIST_FILE=""
PROMPT_FILE=""

# Stats tracking
TOTAL_PRS=0
RESOLVED_PRS=0
MERGED_PRS=0
FAILED_PRS=0

# Start time for global timeout
START_TIME=$(date +%s)
# Default timeout: 3 hours and 30 minutes (12600 seconds)
MAX_RUNTIME=${MAX_RUNTIME:-12600}
# Optional continuous mode for running as a daemon
CONTINUOUS_MODE=${CONTINUOUS_MODE:-false}
# Interval between runs in continuous mode (default 4 hours)
LOOP_INTERVAL=${LOOP_INTERVAL:-14400}
# Dry run mode
DRY_RUN=false

# Parse arguments without shifting, so we can pass them to exec later
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      ;;
    --continuous)
      CONTINUOUS_MODE=true
      ;;
  esac
done

if [ "$DRY_RUN" = "true" ]; then
  log "DRY RUN MODE ENABLED. No changes will be pushed or merged."
fi

cleanup() {
  log "Performing final cleanup of temporary files..."
  rm -f "$ALL_PRS_FILE" "$PR_LIST_FILE" "$PROMPT_FILE"
}
trap cleanup EXIT

# Determine the target repository: prioritize GITHUB_REPOSITORY env var,
# then try to parse it from 'git remote', with a final fallback.
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  REPO="$GITHUB_REPOSITORY"
  log "Using repository from GITHUB_REPOSITORY: $REPO"
else
  # Try 'origin' first, then any remote that looks like a GitHub URL
  REPO=$(git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:\/]//; s/\.git$//' || echo "")
  if [ -z "$REPO" ]; then
    REPO=$(git remote -v | grep "github.com" | head -n 1 | awk '{print $2}' | sed -E 's/.*github.com[:\/]//; s/\.git$//' || echo "")
  fi
  if [ -n "$REPO" ]; then
    log "Detected repository from git remote: $REPO"
  else
    log "Error: Could not determine repository from environment or git remotes."
    exit 1
  fi
fi
API_BASE="https://api.github.com/repos/$REPO"

log "Target Repository: $REPO"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  log "Error: GITHUB_TOKEN is not set."
  exit 1
fi

# Validate GitHub token and permissions
log "Validating GITHUB_TOKEN..."
token_info=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/user")
if printf '%s\n' "$token_info" | jq -e '.message' >/dev/null 2>&1; then
  log "Error: GITHUB_TOKEN validation failed: $(printf '%s\n' "$token_info" | jq -r '.message')"
  # Continue anyway if it's a 403 due to GITHUB_TOKEN limitations in Actions,
  # but log it. If it's 401, we must stop.
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/user")
  if [ "$http_code" -eq 401 ]; then
    exit 1
  fi
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  log "Error: GEMINI_API_KEY is not set."
  exit 1
fi

GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.0-flash}"
log "Using Gemini Model: $GEMINI_MODEL"

# Check for required tools and attempt self-installation of gemini if missing
for tool in jq curl git file sha256sum node python3; do
  if ! command -v "$tool" &> /dev/null; then
    log "Error: $tool is not installed or not in PATH."
    exit 1
  fi
done

if ! command -v gemini &> /dev/null; then
  log "Warning: 'gemini' CLI not found. Attempting to install @google/gemini-cli..."
  if command -v npm &> /dev/null; then
    npm install -g @google/gemini-cli || { log "Error: Failed to install gemini-cli."; exit 1; }
  else
    log "Error: 'npm' not found. Cannot install gemini-cli autonomously."
    exit 1
  fi
fi

# Verify gemini-cli is functional and API key is valid
log "Checking Gemini API health..."
if ! gemini --version &> /dev/null; then
  log "Warning: 'gemini --version' failed. gemini-cli might not be correctly configured."
fi

# Basic connectivity check/health check using a simple prompt
if ! timeout 30 gemini --prompt "ping" --model "$GEMINI_MODEL" --approval-mode yolo --skip-trust &> /dev/null; then
  log "Error: Gemini API health check failed. Please check your GEMINI_API_KEY and network connection."
  # We exit because the core functionality depends on Gemini
  exit 1
fi
log "Gemini API is healthy."

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git config merge.conflictStyle diff3

# Capture original branch to return to it later
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
log "Original branch: $ORIGINAL_BRANCH"

# Fetch all remotes and branches to ensure we have context
log "Fetching all branches..."
git fetch --all

# Function to post a comment to a PR
post_comment() {
  local pr_number=$1
  local body=$2

  # Check if the last comment is the same to avoid spam
  local last_comment_resp
  last_comment_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "$API_BASE/issues/$pr_number/comments?per_page=1&sort=created&direction=desc")

  if printf '%s\n' "$last_comment_resp" | jq -e . >/dev/null 2>&1; then
    local last_comment
    last_comment=$(printf '%s\n' "$last_comment_resp" | jq -r '.[0].body // ""')
    if [ "$last_comment" = "$body" ]; then
      log "Skipping duplicate comment on PR #$pr_number."
      return 0
    fi
  fi

  log "Posting comment to PR #$pr_number..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d "$(jq -n --arg body "$body" '{body: $body}')" \
       "$API_BASE/issues/$pr_number/comments")
  if [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to post comment to PR #$pr_number (HTTP $http_code)"
    return 1
  fi
  return 0
}

# Function to add a label to a PR
add_label() {
  local pr_number=$1
  local label=$2

  if [ "$DRY_RUN" = "true" ]; then
    log "[Label Skip] DRY RUN: Would add label '$label' to PR #$pr_number."
    return 0
  fi

  log "Adding label '$label' to PR #$pr_number..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d "$(jq -n --arg label "$label" '{"labels": [$label]}')" \
       "$API_BASE/issues/$pr_number/labels")
  if [ "$http_code" -ne 200 ] && [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to add label to PR #$pr_number (HTTP $http_code)"
  fi
}

# Function to approve a PR
# Function to check for CHANGES_REQUESTED reviews
check_reviews() {
  local pr_number=$1
  log "Checking reviews for PR #$pr_number..."

  local reviews_resp
  reviews_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        "$API_BASE/pulls/$pr_number/reviews")

  if [ -z "$reviews_resp" ] || ! printf '%s\n' "$reviews_resp" | jq -e . >/dev/null 2>&1; then
    log "Warning: Failed to fetch reviews for PR #$pr_number."
    return 0 # Assume okay if we can't fetch reviews
  fi

  # Check if any review has state CHANGES_REQUESTED. We look at the latest review from each user.
  local active_changes_requested
  active_changes_requested=$(printf '%s\n' "$reviews_resp" | jq '[.[] | {user: (.user.login // "unknown"), state: .state}] | group_by(.user) | map(last) | select(. != null) | .[] | select(.state == "CHANGES_REQUESTED")' 2>/dev/null | jq -s 'length')

  if [ "$active_changes_requested" -gt 0 ]; then
    log "PR #$pr_number has $active_changes_requested active 'CHANGES_REQUESTED' reviews. Skipping."
    return 1
  fi

  return 0
}

approve_pr() {
  local pr_number=$1
  log "Approving PR #$pr_number..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d '{"event":"APPROVE","body":"🤖 Autonomous approval for automated merge."}' \
       "$API_BASE/pulls/$pr_number/reviews")
  if [ "$http_code" -ne 200 ] && [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to approve PR #$pr_number (HTTP $http_code)"
    return 1
  fi
  return 0
}

# Function to check CI status (Statuses and Check Runs)
check_ci_status() {
  local pr_number=$1
  local head_sha=$2
  log "Checking CI status for PR #$pr_number (SHA: $head_sha)..."

  # Check Combined Status
  local status_resp
  status_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$API_BASE/commits/$head_sha/status")

  if [ -z "$status_resp" ] || ! printf '%s\n' "$status_resp" | jq -e . >/dev/null 2>&1; then
    log "Warning: Failed to fetch combined status for PR #$pr_number."
    return 1
  fi

  local status_state
  status_state=$(printf '%s\n' "$status_resp" | jq -r '.state // "pending"')

  # Check Check Runs
  local checks_resp
  checks_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        "$API_BASE/commits/$head_sha/check-runs")

  if [ -z "$checks_resp" ] || ! printf '%s\n' "$checks_resp" | jq -e . >/dev/null 2>&1; then
    log "Warning: Failed to fetch check runs for PR #$pr_number."
    return 1
  fi

  local total_checks
  total_checks=$(printf '%s\n' "$checks_resp" | jq '.total_count // 0')

  # Detailed conclusions summary
  local conclusions_summary
  conclusions_summary=$(printf '%s\n' "$checks_resp" | jq -r '[.check_runs[] | .conclusion // "null"] | group_by(.) | map({conclusion: .[0], count: length}) | .[] | "\(.conclusion)=\(.count)"' | paste -sd "," -)

  # Any failures? (Strictly fail on these)
  local failed_checks
  failed_checks=$(printf '%s\n' "$checks_resp" | jq '[.check_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled" or .conclusion == "action_required")] | length')

  # Any still in progress?
  local in_progress_checks
  in_progress_checks=$(printf '%s\n' "$checks_resp" | jq '[.check_runs[] | select(.status != "completed")] | length')

  log "CI Summary for PR #$pr_number: State=$status_state, TotalChecks=$total_checks, Failed=$failed_checks, InProgress=$in_progress_checks, Conclusions=[$conclusions_summary]"

  if [ "$status_state" = "failure" ] || [ "$status_state" = "error" ]; then
    log "CI status for PR #$pr_number is $status_state. Skipping merge."
    return 1
  fi

  if [ "$failed_checks" -gt 0 ]; then
    log "Found $failed_checks failed check runs (failure, timed_out, cancelled, or action_required) for PR #$pr_number. Skipping merge."
    return 1
  fi

  if [ "$in_progress_checks" -gt 0 ]; then
    log "$in_progress_checks CI checks are still in progress for PR #$pr_number. Skipping merge."
    return 1
  fi

  # If combined status is success
  if [ "$status_state" = "success" ]; then
    log "CI status is success. Ready to merge."
    return 0
  fi

  # If there are no checks at all, and it's been pending for a while, we might consider it safe,
  # but it's safer to require at least one successful check or a 'success' state.
  if [ "$total_checks" -eq 0 ] && [ "$status_state" = "pending" ]; then
    log "CI status is pending and no check runs found. This might be a race condition. Skipping merge for safety."
    return 1
  fi

  log "CI status for PR #$pr_number is $status_state. Skipping merge."
  return 1
}

# Function to poll mergeability with retries
poll_mergeability() {
  local pr_number=$1
  local status="null"
  local attempts=0
  local max_attempts=20

  while [ "$status" = "null" ] && [ $attempts -lt $max_attempts ]; do
    local pr_detail
    # Use a small retry for the curl call itself
    pr_detail=$(curl -s --retry 5 --retry-delay 3 -H "Authorization: Bearer $GITHUB_TOKEN" \
                         -H "Accept: application/vnd.github.v3+json" \
                         "$API_BASE/pulls/$pr_number")

    if [ -z "$pr_detail" ] || ! printf '%s\n' "$pr_detail" | jq -e . >/dev/null 2>&1; then
      log "Warning: Received empty or invalid JSON response from GitHub API for PR #$pr_number."
      status="null"
    else
      status=$(printf '%s\n' "$pr_detail" | jq -r 'if .mergeable == null then "null" else .mergeable end' 2>/dev/null || echo "null")
    fi

    if [ "$status" = "null" ]; then
      log "Mergeability status for PR #$pr_number is null (calculating). Attempt $((attempts+1))/$max_attempts. Waiting 30s..."
      sleep 30
      attempts=$((attempts+1))
    fi
  done

  if [ "$status" = "null" ]; then
    log "Warning: Mergeability for PR #$pr_number is still null after $max_attempts attempts."
  fi

  echo "$status"
}

# 1. Fetch all open pull requests (handling pagination)
log "Step 1: Fetching all open pull requests for $REPO..."
page=1
ALL_PRS_FILE=$(mktemp)
echo "[]" > "$ALL_PRS_FILE"

while : ; do
  log "Fetching page $page of PRs..."
  # Retry loop for PR fetching
  fetch_attempt=1
  max_fetch_attempts=3
  prs_page=""
  while [ $fetch_attempt -le $max_fetch_attempts ]; do
    prs_page=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "$API_BASE/pulls?state=open&per_page=100&page=$page&sort=created&direction=asc")
    if [ -n "$prs_page" ] && printf '%s\n' "$prs_page" | jq -e . >/dev/null 2>&1; then
      break
    fi
    log "Warning: Failed to fetch PRs (attempt $fetch_attempt/$max_fetch_attempts). Retrying in 5s..."
    sleep 5
    fetch_attempt=$((fetch_attempt + 1))
  done

  # Check if we got an error message instead of an array
  if printf '%s\n' "$prs_page" | jq -e '.message' >/dev/null 2>&1; then
    msg=$(printf '%s\n' "$prs_page" | jq -r '.message')
    log "Error from GitHub API on page $page: $msg"
    if [[ "$msg" == *"rate limit exceeded"* ]]; then
      log "Rate limit exceeded. Stopping PR fetching."
      break
    fi
    exit 1
  fi

  count=$(printf '%s\n' "$prs_page" | jq '. | length')
  if [ "$count" -eq 0 ]; then
    break
  fi

  # Merge current page into total list
  temp_all_prs=$(mktemp)
  if jq -s 'add' "$ALL_PRS_FILE" <(printf '%s\n' "$prs_page") > "$temp_all_prs"; then
    mv "$temp_all_prs" "$ALL_PRS_FILE"
  else
    log "Error: Failed to process PR JSON on page $page."
    rm -f "$temp_all_prs"
    exit 1
  fi

  page=$((page+1))
done

# Log remaining rate limit
rate_limit_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/rate_limit")
if printf '%s\n' "$rate_limit_resp" | jq -e . >/dev/null 2>&1; then
  remaining=$(printf '%s\n' "$rate_limit_resp" | jq -r '.resources.core.remaining')
  limit=$(printf '%s\n' "$rate_limit_resp" | jq -r '.resources.core.limit')
  reset=$(printf '%s\n' "$rate_limit_resp" | jq -r '.resources.core.reset')
  reset_date=$(date -d "@$reset" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$reset")
  log "GitHub API Rate Limit: $remaining/$limit (Resets at: $reset_date)"
fi

total_count=$(jq '. | length' "$ALL_PRS_FILE")
log "Found $total_count open pull requests in total."

# Function to process a single PR
process_pr() {
  local pr="$1"
  local number head_ref base_ref head_repo head_clone_url is_draft pr_title pr_body maintainer_can_modify pr_url file

  number=$(printf '%s\n' "$pr" | jq -r '.number')
  head_ref=$(printf '%s\n' "$pr" | jq -r '.head.ref')
  base_ref=$(printf '%s\n' "$pr" | jq -r '.base.ref')
  head_repo=$(printf '%s\n' "$pr" | jq -r '.head.repo.full_name')
  head_clone_url=$(printf '%s\n' "$pr" | jq -r '.head.repo.clone_url')
  is_draft=$(printf '%s\n' "$pr" | jq -r '.draft')
  pr_title=$(printf '%s\n' "$pr" | jq -r '.title')
  pr_body=$(printf '%s\n' "$pr" | jq -r '.body')
  pr_url=$(printf '%s\n' "$pr" | jq -r '.html_url')
  maintainer_can_modify=$(printf '%s\n' "$pr" | jq -r '.maintainer_can_modify // false')
  local pr_labels
  pr_labels=$(printf '%s\n' "$pr" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

  log ""
  log "=== Processing PR #$number ($head_ref -> $base_ref) ==="
  log "PR URL: $pr_url"
  log "PR Title: $pr_title"
  log "PR Labels: [$pr_labels]"

  if [ "$is_draft" = "true" ]; then
    log "PR #$number is a draft. Skipping."
    return 0
  fi

  # Skip PRs with WIP or HOLD in title or labels
  if echo "$pr_title" | grep -qiE "WIP|HOLD|\[WIP\]|DO NOT MERGE"; then
    log "PR #$number title suggests it's not ready (WIP/HOLD). Skipping."
    return 0
  fi

  if echo "$pr_labels" | grep -qiE "wip|hold|do-not-merge|status: hold"; then
    log "PR #$number labels suggest it's not ready (wip/hold). Skipping."
    return 0
  fi

  # Ensure a clean state for each iteration
  git reset --hard HEAD
  git clean -fd

  # Use token in URL for fork pushing
  local authenticated_head_url
  authenticated_head_url=$(printf '%s\n' "$head_clone_url" | sed "s|https://|https://x-access-token:${GITHUB_TOKEN}@|")

  # Fetch the PR branch
  log "[Fetch] Fetching $head_ref from $head_repo..."
  if ! git fetch "$authenticated_head_url" "$head_ref"; then
    log "[Fetch Error] Failed to fetch PR branch from $head_repo."
    return 1
  fi
  local pr_head_commit
  pr_head_commit=$(git rev-parse FETCH_HEAD)
  log "[Fetch] Successfully fetched head at $pr_head_commit"

  # Fetch the base branch
  log "[Fetch] Fetching origin/$base_ref..."
  if ! git fetch origin "$base_ref"; then
    log "[Fetch Error] Failed to fetch base branch origin/$base_ref."
    return 1
  fi
  local base_branch_head
  base_branch_head=$(git rev-parse FETCH_HEAD)
  log "[Fetch] Successfully fetched base at $base_branch_head"

  # Check if PR is behind base
  local behind_count
  behind_count=$(git rev-list --count "$pr_head_commit..$base_branch_head")

  # Check mergeability via API
  log "[API] Polling mergeability for PR #$number..."
  local mergeable
  mergeable=$(poll_mergeability "$number")

  if [ "$mergeable" = "false" ] || [ "$behind_count" -gt 0 ]; then
    log "[Analysis] PR #$number needs update (conflicted: $mergeable, behind: $behind_count)."

    # Avoid messing with forks if permissions are restricted
    if [ "$head_repo" != "$REPO" ] && [ "$maintainer_can_modify" != "true" ]; then
      log "PR #$number is from a fork ($head_repo) and maintainer edits are disabled. Skipping automated update."
      post_comment "$number" "🤖 This PR is from a fork and 'Allow edits from maintainers' is disabled. To enable autonomous conflict resolution and automatic updates, please check the 'Allow edits from maintainers' box on your PR."
    else
      log "Attempting automated update/resolution for PR #$number..."

      # Use a unique local branch name to avoid collisions
      local local_branch="auto-resolve-pr-$number"
      log "Checking out local branch $local_branch from $pr_head_commit..."
      git checkout -B "$local_branch" "$pr_head_commit"

      log "[Merge] Attempting to merge base branch ($base_branch_head) into $local_branch..."
      if ! git merge "$base_branch_head" --no-edit; then
        log "[Merge] Merge failed with conflicts. Identifying files..."
        post_comment "$number" "🤖 PR #$number has conflicts. Attempting autonomous resolution via Gemini CLI ($GEMINI_MODEL)..."

        local conflicts_file
        conflicts_file=$(mktemp)
        git diff --name-only --diff-filter=U > "$conflicts_file"

        while read -u 4 file; do
          if [ -z "$file" ]; then continue; fi
          if [ ! -f "$file" ]; then
             log "File $file no longer exists. Skipping."
             continue
          fi

          # Skip binary files
          if file --mime "$file" | grep -q "binary"; then
            log "Skipping binary file: $file"
            continue
          fi

          log "[Resolve] Resolving conflicts in $file..."
          # Calculate checksum before resolution
          local pre_checksum post_checksum gemini_status
          pre_checksum=$(sha256sum "$file" | awk '{print $1}')

          # Use gemini-cli to resolve conflicts autonomously with retries
          local attempt=1
          local max_attempts=3
          local resolved=false

          while [ $attempt -le $max_attempts ]; do
            log "[Resolve] Resolution attempt $attempt of $max_attempts for $file..."

            # PROMPT GENERATION (Hardened against injection from PR metadata)
            PROMPT_FILE=$(mktemp)
            {
              printf "You are an autonomous AI engineer working in a GitHub Actions CI environment.\n"
              printf "Your task is to resolve git merge conflicts in the file '%s' for Pull Request #%s.\n\n" "$file" "$number"
              printf "### CONTEXT\n"
              printf "PR Title: %s\n" "$pr_title"
              printf "PR Description: %s\n" "$pr_body"
              printf "Global Project Context: Refer to 'GEMINI.md' in the root directory for project-specific rules and instructions.\n\n"
              printf "### CONFLICT STRUCTURE\n"
              printf "The file contains git merge conflicts. In this context:\n"
              printf "- '<<<<<<< HEAD' represents the current state of the Pull Request branch.\n"
              printf "- The section after '=======' until '>>>>>>>' represents the incoming changes from the Target Base branch ('%s').\n\n" "$base_ref"
              printf "### OBJECTIVE\n"
              printf "You are the primary decision-maker for this resolution. Use your tools to:\n"
              printf "1. MANDATORY: Use your 'read_file' tool to read the file '%s' and identify all conflict markers (<<<<<<<, =======, >>>>>>>). You MUST read the entire file to ensure you have full context.\n" "$file"
              printf "2. MANDATORY: Use your 'read_file' tool to read 'GEMINI.md' in the root directory and adhere to all project-wide rules and architectural patterns defined there.\n"
              printf "3. Resolve the conflicts accurately, preserving the intended logic from both branches. If changes are mutually exclusive, prioritize the base branch's architecture unless the PR's intent is clearly superior.\n"
              printf "4. MANDATORY: Use your 'write_file' tool to write the fully resolved, clean content back to '%s'. You must overwrite the file with the final version. DO NOT just output the code in your response; use the tool.\n" "$file"
              printf "5. MANDATORY: Ensure ABSOLUTELY NO conflict markers remain. Triple check for '<<<<<<<', '=======', and '>>>>>>>' before finalizing.\n"
              printf "6. MANDATORY: Verify the resulting code is syntactically correct and functional. Run a syntax check using available tools and FIX any errors found:\n"
              printf "   - For JavaScript: 'node --check %s'\n" "$file"
              printf "   - For TypeScript: Use 'tsc --noEmit %s' if available.\n" "$file"
              printf "   - For Python: 'python3 -m py_compile %s'\n" "$file"
              printf "   - For Shell scripts: 'bash -n %s'\n" "$file"
              printf "   - For JSON: 'jq . %s'\n" "$file"
              printf "   - For YAML: 'python3 -c \"import yaml, sys; yaml.safe_load(sys.stdin)\" < %s'\n" "$file"
              printf "   - For SQL: 'sqlite3 :memory: \".read '\''%s'\''\"'\n" "$file"
              printf "   - For Ruby: 'ruby -c %s'\n" "$file"
              printf "   - For PHP: 'php -l %s'\n" "$file"
              printf "   - For Go: 'gofmt -e %s'\n" "$file"
              printf "   - For HTML/CSS: Use basic pattern matching or available linters to ensure tag/bracket balance.\n"
              printf "7. MANDATORY: Explore the repository using 'ls -R' to gather context (imports, variable definitions) for a correct resolution. Pay special attention to dependency changes.\n"
              printf "8. MANDATORY: After resolving, proactively check for side effects using 'grep' to ensure no logic was broken elsewhere.\n"
              printf "9. Ensure the resulting code is syntactically correct and preserves intended logic.\n"
              printf "10. For configuration files (package.json, requirements.txt), maintain a valid and consistent structure.\n\n"
              printf "### EXECUTION GUIDELINES\n"
              printf "- You are in 'YOLO' mode; your tool calls are auto-approved. Use them decisively and autonomously.\n"
              printf "- MANDATORY: Use 'read_file' for all file reading and 'write_file' for all file writing. DO NOT simply output code blocks in your response.\n"
              printf "- MANDATORY: Use 'run_shell_command' for syntax checks and repository exploration ('ls -R', 'grep').\n"
              printf "- Use 'list_directory' or 'glob' to find relevant files if you need more context on imports or dependencies.\n"
              printf "- DO NOT attempt to use 'git' commands (add, commit, push). The environment script handles git state; your job is strictly file resolution.\n"
              printf "- If you cannot resolve the conflict or the file is too large/complex, explain why and stop.\n"
              printf "- Perform a final self-verification by reading the file back after writing to ensure it's correct.\n\n"
              printf "Focus entirely on using your tools to resolve and write the file '%s'. Do not give a conversational response; just use your tools.\n" "$file"
            } > "$PROMPT_FILE"

            log "[Gemini] Invoking Gemini CLI ($GEMINI_MODEL) for $file (5m timeout)..."
            set +e
            # Redirect stdin from PROMPT_FILE. gemini CLI will read the prompt from here.
            timeout 300 gemini --model "$GEMINI_MODEL" --prompt "" --approval-mode yolo --skip-trust < "$PROMPT_FILE"
            gemini_status=$?
            rm -f "$PROMPT_FILE"
            PROMPT_FILE=""
            set -e

            if [ $gemini_status -eq 0 ]; then
              log "[Gemini] Finished processing $file. Verifying results..."
              post_checksum=$(sha256sum "$file" | awk '{print $1}')
              if [ "$pre_checksum" = "$post_checksum" ]; then
                log "[Gemini Warning] File $file was not modified by Gemini CLI in attempt $attempt."
              elif grep -qE "<<<<<<<|=======|>>>>>>>" "$file"; then
                log "[Gemini Warning] Conflict markers still present in $file after attempt $attempt."
              else
                log "[Verify] Conflict markers successfully removed from $file. Performing secondary syntax check..."
                local syntax_ok=true
                local syntax_err=""
                local tool_found=true
                case "$file" in
                  *.js|*.mjs)
                    if command -v node &>/dev/null; then
                      syntax_err=$(node --check "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.ts|*.tsx)
                    if command -v npx &>/dev/null; then
                      # TypeScript verification in isolation is tricky due to dependencies.
                      # We use a more relaxed check that focuses on syntax.
                      syntax_err=$(npx -p typescript tsc "$file" --noEmit --target esnext --module esnext --esModuleInterop --skipLibCheck 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.py)
                    if command -v python3 &>/dev/null; then
                      syntax_err=$(python3 -m py_compile "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.sh)
                    if command -v bash &>/dev/null; then
                      syntax_err=$(bash -n "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.json)
                    if command -v jq &>/dev/null; then
                      syntax_err=$(jq . "$file" 2>&1 > /dev/null) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.yml|*.yaml)
                    if command -v python3 &>/dev/null && python3 -c "import yaml" &>/dev/null; then
                      syntax_err=$(python3 -c "import yaml, sys; yaml.safe_load(sys.stdin)" < "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.sql)
                    if command -v sqlite3 &>/dev/null; then
                      # Use stdin redirection to avoid filename quoting issues in .read
                      syntax_err=$(sqlite3 :memory: ".read /dev/stdin" < "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.rb)
                    if command -v ruby &>/dev/null; then
                      syntax_err=$(ruby -c "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.php)
                    if command -v php &>/dev/null; then
                      syntax_err=$(php -l "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                  *.go)
                    if command -v gofmt &>/dev/null; then
                      syntax_err=$(gofmt -e "$file" 2>&1) || syntax_ok=false
                    else
                      tool_found=false
                    fi
                    ;;
                esac

                if [ "$tool_found" = "false" ]; then
                  log "[Verify Warning] No syntax check tool found for $file. Skipping secondary check."
                fi

                if [ "$syntax_ok" = "true" ]; then
                  log "[Verify Success] Syntax check passed (or skipped) for $file."
                  git add "$file"
                  resolved=true
                  break
                else
                  log "[Verify Error] Secondary syntax check failed for $file in attempt $attempt:"
                  printf "%s\n" "$syntax_err" | while read -r line; do log "  > $line"; done
                fi
              fi
            else
              log "[Gemini Error] Gemini CLI failed with exit code $gemini_status for $file in attempt $attempt."
            fi
            attempt=$((attempt + 1))
            [ $attempt -le $max_attempts ] && sleep 10
          done

          if [ "$resolved" = "false" ]; then
            log "Error: Failed to resolve $file after $max_attempts attempts."
            continue
          else
            log "File $file was successfully resolved and verified."
          fi
        done 4< "$conflicts_file"
        rm -f "$conflicts_file"

        # Final check for remaining conflicts
        local remaining_conflicts
        remaining_conflicts=$(git diff --name-only --diff-filter=U)
        if [ -n "$remaining_conflicts" ]; then
          log "Error: Unresolved conflicts remain in: $remaining_conflicts. Aborting merge for PR #$number."
          git merge --abort
          post_comment "$number" "❌ Failed to autonomously resolve all conflicts. Remaining: $remaining_conflicts"
          return 1
        fi

        if [ -n "$(git status --short)" ]; then
          log "Committing resolved conflicts for PR #$number..."
          git commit -m "chore: auto-resolve merge conflicts for PR #$number via gemini-cli"
        else
          log "No changes to commit after conflict resolution attempt."
        fi
      else
        log "Merge was successful (no conflicts found)."
      fi

      # Check if we have new commits to push
      if [ $(git rev-list --count "$pr_head_commit..HEAD") -gt 0 ]; then
        if [ "$DRY_RUN" = "true" ]; then
          log "[Push Skip] DRY RUN: Would push updated changes to $head_repo ($head_ref)."
          RESOLVED_PRS=$((RESOLVED_PRS + 1))
          return 0
        fi

        # Get list of changed files for the comment
        local changed_files
        changed_files=$(git diff --name-only "$pr_head_commit..HEAD" | sed 's/^/- /' || echo "")

        log "[Push] Pushing updated changes to $head_repo ($head_ref)..."
        if git push "$authenticated_head_url" "HEAD:$head_ref"; then
          log "[Push Success] Successfully updated PR #$number and pushed to $head_ref."
          local comment_body
          comment_body=$(printf "✅ Successfully updated PR #%s with latest changes from %s and resolved conflicts.\n\n**Resolved Files:**\n%s" "$number" "$base_ref" "$changed_files")
          post_comment "$number" "$comment_body"
          add_label "$number" "auto-resolved"
          RESOLVED_PRS=$((RESOLVED_PRS + 1))

          # Wait a bit for GitHub to re-calculate mergeability after push
          log "[API] Waiting for GitHub to re-calculate mergeability..."
          sleep 15
          mergeable=$(poll_mergeability "$number")
        else
          log "[Push Error] Failed to push updated changes to $head_ref."
          post_comment "$number" "❌ Failed to push updated changes to $head_ref. Please check if the branch is protected."
          return 1
        fi
      else
        log "No changes to commit or push for PR #$number."
      fi
    fi
  elif [ "$mergeable" = "true" ]; then
    log "PR #$number is mergeable and up to date."
  fi

  # 3. Squash and Merge
  if [ "$mergeable" = "true" ]; then
    log "[Merge] PR #$number is mergeable. Proceeding to squash-merge."
    # Final poll to ensure PR state is fresh before merge
    mergeable=$(poll_mergeability "$number")
    if [ "$mergeable" != "true" ]; then
      log "[Merge Skip] PR #$number is no longer mergeable ($mergeable) after final poll."
      return 1
    fi

    # Get the latest head SHA to check CI status accurately
    local current_head_sha_resp
    current_head_sha_resp=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                            -H "Accept: application/vnd.github.v3+json" \
                            "$API_BASE/pulls/$number")

    if ! printf '%s\n' "$current_head_sha_resp" | jq -e . >/dev/null 2>&1; then
      log "[Merge Skip] Failed to fetch PR details for #$number to verify head SHA."
      return 1
    fi

    local current_head_sha
    current_head_sha=$(printf '%s\n' "$current_head_sha_resp" | jq -r '.head.sha // empty')

    if [ -z "$current_head_sha" ] || [ "$current_head_sha" = "null" ]; then
      log "[Merge Skip] Could not determine head SHA for PR #$number."
      return 1
    fi

    if ! check_ci_status "$number" "$current_head_sha"; then
      log "[Merge Skip] CI check failed or still in progress for PR #$number."
      return 1
    fi

    if ! check_reviews "$number"; then
      log "[Merge Skip] Human reviews require changes for PR #$number."
      return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
       log "[Merge Skip] DRY RUN: Would approve and squash-merge PR #$number."
       MERGED_PRS=$((MERGED_PRS + 1))
       return 0
    fi

    approve_pr "$number"

    local merged="false"
    local msg="Unknown error"
    local http_code=0

    if command -v gh &> /dev/null; then
      log "[Merge] Attempting squash and merge for PR #$number via GitHub CLI (gh)..."
      if gh pr merge "$number" --squash --subject "chore: squash merge PR #$number ($pr_title)" --body "chore: autonomous squash merge PR #$number via gemini-cli" --repo "$REPO"; then
        merged="true"
        http_code=200
        log "[Merge Success] GitHub CLI squash-merge successful for PR #$number."
      else
        log "[Merge Warning] GitHub CLI merge failed for PR #$number. Falling back to API."
      fi
    fi

    if [ "$merged" != "true" ]; then
      log "[Merge] Attempting squash and merge for PR #$number via GitHub API..."
      # Capture HTTP status code and response body
      local merge_output merge_response
      merge_output=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
                                     -H "Accept: application/vnd.github.v3+json" \
                                     -d "$(jq -n --arg number "$number" --arg title "$pr_title" '{merge_method: "squash", commit_title: ("chore: squash merge PR #" + $number + " (" + $title + ")"), commit_message: ("chore: autonomous squash merge PR #" + $number + " via gemini-cli")}')" \
                                     "$API_BASE/pulls/$number/merge")

      merge_response=$(printf '%s\n' "$merge_output" | head -n -1)
      http_code=$(printf '%s\n' "$merge_output" | tail -n 1)

      if [ -z "$merge_response" ] || ! printf '%s\n' "$merge_response" | jq -e . >/dev/null 2>&1; then
        merged="false"
        msg="Empty or invalid JSON response from GitHub API"
      else
        merged=$(printf '%s\n' "$merge_response" | jq -r 'if .merged == null then false else .merged end' 2>/dev/null || printf "false")
        msg=$(printf '%s\n' "$merge_response" | jq -r 'if .message == null then "Unknown error" else .message end' 2>/dev/null || printf "Unknown error")
      fi
    fi

    if [ "$merged" = "true" ] && ([ "$http_code" -eq 200 ] || [ "$http_code" -eq 0 ]); then
      log "SUCCESS: PR #$number has been squash-merged."
      post_comment "$number" "✅ PR #$number has been successfully squash-merged after autonomous verification."
      MERGED_PRS=$((MERGED_PRS + 1))
    else
      log "FAILED (HTTP $http_code): Could not merge PR #$number. Reason: $msg"
      log "Full API response: $merge_response"
      post_comment "$number" "❌ Failed to squash-merge PR #$number (HTTP $http_code). Reason: $msg. Full details logged in GitHub Actions."
      return 1
    fi
  else
    log "PR #$number is not mergeable ($mergeable). Skipping merge."
  fi

  # Return to base branch (clean up)
  git checkout "$base_ref" || true
}

# Loop through each PR using a temporary file to avoid subshell issues with pipe
log "Step 2: Processing pull requests one by one..."
PR_LIST_FILE=$(mktemp)
jq -c '.[]' "$ALL_PRS_FILE" > "$PR_LIST_FILE"

while read -u 3 -r pr; do
  # Check for global timeout
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ $ELAPSED -ge $MAX_RUNTIME ]; then
    log "Global timeout of ${MAX_RUNTIME}s reached. Skipping remaining PRs."
    break
  fi

  TOTAL_PRS=$((TOTAL_PRS + 1))
  # Use a subshell to ensure failures in one PR don't stop the script.
  # We use a temporary file to capture side effects like stat updates from the subshell if needed,
  # but for simple stats, we'll just track them in the main loop or accept they stay in subshell.
  # Actually, to keep stats, we should not use a subshell if we want to increment variables,
  # or we use a file. Let's use a file for robust stat tracking.
  if ! process_pr "$pr"; then
    log "Error occurred while processing PR. Continuing to next PR..."
    FAILED_PRS=$((FAILED_PRS + 1))
  fi
done 3< "$PR_LIST_FILE"

log ""
log "=== Final Summary Report ==="
log "Total PRs processed: $TOTAL_PRS"
log "PRs resolved/updated: $RESOLVED_PRS"
log "PRs successfully merged: $MERGED_PRS"
log "PRs that failed processing: $FAILED_PRS"
log "============================"

# Write to GitHub Actions Job Summary if available
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### 🤖 Autonomous PR Resolution Summary"
    echo "| Metric | Count |"
    echo "| :--- | :--- |"
    echo "| Total PRs Processed | $TOTAL_PRS |"
    echo "| PRs Resolved/Updated | $RESOLVED_PRS |"
    echo "| PRs Successfully Merged | $MERGED_PRS |"
    echo "| PRs Failed Processing | $FAILED_PRS |"
    echo ""
    echo "*Run Duration: $(( $(date +%s) - START_TIME )) seconds*"
  } >> "$GITHUB_STEP_SUMMARY"
fi

# Return to the original branch
log "Returning to original branch: $ORIGINAL_BRANCH"
git checkout "$ORIGINAL_BRANCH" || log "Warning: Failed to return to original branch $ORIGINAL_BRANCH"

log "Finished processing all pull requests."

if [ "$CONTINUOUS_MODE" = "true" ]; then
  CURRENT_TIME=$(date +%s)
  RUN_DURATION=$((CURRENT_TIME - START_TIME))
  WAIT_TIME=$((LOOP_INTERVAL - RUN_DURATION))

  if [ $WAIT_TIME -gt 0 ]; then
    log "Continuous mode enabled. Run took ${RUN_DURATION}s. Waiting ${WAIT_TIME}s ($((WAIT_TIME / 60)) minutes) before next run..."
    sleep "$WAIT_TIME"
  else
    log "Continuous mode enabled. Run took ${RUN_DURATION}s, which exceeds LOOP_INTERVAL (${LOOP_INTERVAL}s). Starting next run immediately."
  fi

  # Re-execute the script
  exec "$0" "$@"
fi
