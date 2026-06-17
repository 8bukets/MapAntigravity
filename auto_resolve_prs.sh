#!/bin/bash
# auto_resolve_prs.sh

set -euo pipefail

# Helper function for logging with timestamps
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Global variables for cleanup
ALL_PRS_FILE=""
PR_LIST_FILE=""
PROMPT_FILE=""

cleanup() {
  log "Performing final cleanup of temporary files..."
  rm -f "$ALL_PRS_FILE" "$PR_LIST_FILE" "$PROMPT_FILE"
}
trap cleanup EXIT

# Use GITHUB_REPOSITORY if available, otherwise fallback to parsing origin remote
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  REPO=$(git remote get-url origin | sed -E 's/.*github.com[:\/]//; s/\.git$//')
else
  REPO="$GITHUB_REPOSITORY"
fi
# Final fallback if both fail
REPO="${REPO:-8bukets/MapAntigravity}"
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

# Check for required tools
for tool in jq gemini curl git file sha256sum node python3; do
  if ! command -v "$tool" &> /dev/null; then
    log "Error: $tool is not installed or not in PATH."
    exit 1
  fi
done

# Verify gemini-cli is functional
if ! gemini --version &> /dev/null; then
  log "Warning: 'gemini --version' failed. gemini-cli might not be correctly configured."
fi

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Fetch all remotes and branches to ensure we have context
log "Fetching all branches..."
git fetch --all

# Function to post a comment to a PR
post_comment() {
  local pr_number=$1
  local body=$2

  # Check if the last comment is the same to avoid spam
  local last_comment
  last_comment=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "$API_BASE/issues/$pr_number/comments?per_page=1&sort=created&direction=desc" \
                      | jq -r '.[0].body // ""')

  if [ "$last_comment" = "$body" ]; then
    log "Skipping duplicate comment on PR #$pr_number."
    return 0
  fi

  log "Posting comment to PR #$pr_number..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d "$(jq -n --arg body "$body" '{body: $body}')" \
       "$API_BASE/issues/$pr_number/comments")
  if [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to post comment to PR #$pr_number (HTTP $http_code)"
  fi
}

# Function to approve a PR
approve_pr() {
  local pr_number=$1
  log "Approving PR #$pr_number..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d '{"event":"APPROVE","body":"🤖 Autonomous approval for automated merge."}' \
       "$API_BASE/pulls/$pr_number/reviews")
  if [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to approve PR #$pr_number (HTTP $http_code)"
  fi
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

  # Any failures?
  local failed_checks
  failed_checks=$(printf '%s\n' "$checks_resp" | jq '[.check_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out")] | length')

  # Any still in progress?
  local in_progress_checks
  in_progress_checks=$(printf '%s\n' "$checks_resp" | jq '[.check_runs[] | select(.status != "completed")] | length')

  log "CI Summary for PR #$pr_number: State=$status_state, TotalChecks=$total_checks, Failed=$failed_checks, InProgress=$in_progress_checks"

  if [ "$status_state" = "failure" ] || [ "$status_state" = "error" ] || [ "$failed_checks" -gt 0 ]; then
    log "CI status for PR #$pr_number is failing. Skipping merge."
    return 1
  fi

  if [ "$in_progress_checks" -gt 0 ]; then
    log "CI checks are still in progress for PR #$pr_number. Skipping merge."
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

# Function to poll mergeability
poll_mergeability() {
  local pr_number=$1
  local status="null"
  local attempts=0
  local max_attempts=12

  while [ "$status" = "null" ] && [ $attempts -lt $max_attempts ]; do
    local pr_detail
    pr_detail=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                         -H "Accept: application/vnd.github.v3+json" \
                         "$API_BASE/pulls/$pr_number")

    if [ -z "$pr_detail" ] || ! printf '%s\n' "$pr_detail" | jq -e . >/dev/null 2>&1; then
      log "Warning: Received empty or invalid JSON response from GitHub API for PR #$pr_number."
      status="null"
    else
      status=$(printf '%s\n' "$pr_detail" | jq -r 'if .mergeable == null then "null" else .mergeable end' 2>/dev/null || echo "null")
    fi

    if [ "$status" = "null" ]; then
      log "Mergeability status for PR #$pr_number is null (calculating). Attempt $((attempts+1))/$max_attempts. Waiting 15s..."
      sleep 15
      attempts=$((attempts+1))
    fi
  done
  echo "$status"
}

# 1. Fetch all open pull requests (handling pagination)
log "Step 1: Fetching all open pull requests for $REPO..."
page=1
ALL_PRS_FILE=$(mktemp)
echo "[]" > "$ALL_PRS_FILE"

while : ; do
  log "Fetching page $page of PRs..."
  prs_page=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "$API_BASE/pulls?state=open&per_page=100&page=$page&sort=created&direction=asc")

  # Check if we got an error message instead of an array
  if printf '%s\n' "$prs_page" | jq -e '.message' >/dev/null 2>&1; then
    log "Error from GitHub API: $(printf '%s\n' "$prs_page" | jq -r '.message')"
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

total_count=$(jq '. | length' "$ALL_PRS_FILE")
log "Found $total_count open pull requests in total."

# Function to process a single PR
process_pr() {
  local pr="$1"
  local number head_ref base_ref head_repo head_clone_url is_draft pr_title pr_body maintainer_can_modify

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

  log ""
  log "=== Processing PR #$number ($head_ref -> $base_ref) ==="
  log "PR URL: $pr_url"

  if [ "$is_draft" = "true" ]; then
    log "PR #$number is a draft. Skipping."
    return 0
  fi

  # Ensure a clean state for each iteration
  git reset --hard HEAD
  git clean -fd

  # Use token in URL for fork pushing
  local authenticated_head_url
  authenticated_head_url=$(printf '%s\n' "$head_clone_url" | sed "s|https://|https://x-access-token:${GITHUB_TOKEN}@|")

  # Fetch the PR branch
  log "Fetching $head_ref from $head_repo..."
  if ! git fetch "$authenticated_head_url" "$head_ref"; then
    log "Error: Failed to fetch PR branch from $head_repo."
    return 0
  fi
  local pr_head_commit
  pr_head_commit=$(git rev-parse FETCH_HEAD)

  # Fetch the base branch
  log "Fetching origin/$base_ref..."
  if ! git fetch origin "$base_ref"; then
    log "Error: Failed to fetch base branch origin/$base_ref."
    return 0
  fi

  # Check if PR is behind base
  local behind_count
  behind_count=$(git rev-list --count "$pr_head_commit..origin/$base_ref")

  # Check mergeability via API
  local mergeable
  mergeable=$(poll_mergeability "$number")

  if [ "$mergeable" = "false" ] || [ "$behind_count" -gt 0 ]; then
    log "PR #$number needs update (conflicted: $mergeable, behind: $behind_count)."

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

      log "Attempting to merge origin/$base_ref into $local_branch..."
      if ! git merge "origin/$base_ref" --no-edit; then
        log "Merge failed with conflicts. Identifying files..."
        local conflicts
        conflicts=$(git diff --name-only --diff-filter=U)

        post_comment "$number" "🤖 PR #$number has conflicts. Attempting autonomous resolution via Gemini CLI ($GEMINI_MODEL)..."

        for file in $conflicts; do
          if [ ! -f "$file" ]; then
             log "File $file no longer exists. Skipping."
             continue
          fi

          # Skip binary files
          if file --mime "$file" | grep -q "binary"; then
            log "Skipping binary file: $file"
            continue
          fi

          log "Resolving conflicts in $file..."
          # Calculate checksum before resolution
          local pre_checksum post_checksum gemini_status
          pre_checksum=$(sha256sum "$file" | awk '{print $1}')

          # Use gemini-cli to resolve conflicts autonomously
          # We use --approval-mode yolo and --skip-trust for autonomous automatic resolution

          # PROMPT GENERATION (Hardened against injection from PR metadata)
          PROMPT_FILE=$(mktemp)
          {
            printf "You are an autonomous AI engineer working in a GitHub Actions CI environment.\n"
            printf "Your task is to resolve git merge conflicts in the file '%s' for Pull Request #%s.\n\n" "$file" "$number"
            printf "### CONTEXT\n"
            printf "PR Title: %s\n" "$pr_title"
            printf "PR Description: %s\n\n" "$pr_body"
            printf "### OBJECTIVE\n"
            printf "Use your tools to:\n"
            printf "1. MANDATORY: Use your 'read_file' tool to read the file '%s' and identify all conflict markers (<<<<<<<, =======, >>>>>>>).\n" "$file"
            printf "2. Resolve the conflicts accurately, preserving the intended logic from both branches where appropriate. Ensure the resolution aligns with the overall project architecture.\n"
            printf "3. MANDATORY: Use your 'write_file' (or equivalent) tool to write the fully resolved, clean content back to '%s'. You must overwrite the file with the final version.\n" "$file"
            printf "4. Ensure ABSOLUTELY NO conflict markers (<<<<<<<, =======, >>>>>>>) remain in the file.\n"
            printf "5. MANDATORY: Verify the resulting code is syntactically correct and functional. Run a syntax check using available tools (via 'run_shell_command' if needed):\n"
            printf "   - For JavaScript: 'node --check %s'\n" "$file"
            printf "   - For TypeScript: Use 'tsc --noEmit %s' if available, otherwise 'node --check'.\n" "$file"
            printf "   - For Python: 'python3 -m py_compile %s'\n" "$file"
            printf "   - For Shell scripts: 'bash -n %s'\n" "$file"
            printf "   - For JSON: 'jq . %s'\n" "$file"
            printf "   - For HTML/CSS: Use basic pattern matching or available linters to ensure tag/bracket balance.\n"
            printf "6. MANDATORY: Use your tools like 'ls -R', 'find', or 'grep' to explore the repository and gather necessary context (e.g., checking imports, variable definitions, or function signatures in other files) to ensure your resolution is correct and functional. Pay special attention to changes in dependencies or shared utilities.\n"
            printf "7. After resolving, proactively check for side effects. Use 'grep' to see if your changes affect other files that depend on the modified code.\n"
            printf "8. Ensure the resulting code preserves the intended logic and remains consistent with the rest of the project.\n"
            printf "9. If the conflict is in a configuration file (like package.json or requirements.txt), ensure the resulting structure is valid and consistent.\n\n"
            printf "You are in 'YOLO' mode, meaning your actions will be auto-approved. Work efficiently and autonomously to resolve the conflict and finalize the file.\n"
            printf "Do not provide any conversational response or explanation. Focus entirely on using your tools to resolve and write the file '%s'.\n" "$file"
          } > "$PROMPT_FILE"

          log "Invoking Gemini CLI ($GEMINI_MODEL) for $file..."
          set +e
          gemini --model "$GEMINI_MODEL" --prompt "" --approval-mode yolo --skip-trust < "$PROMPT_FILE"
          gemini_status=$?
          rm -f "$PROMPT_FILE"
          PROMPT_FILE=""
          set -e

          if [ $gemini_status -eq 0 ]; then
            log "Gemini CLI finished processing $file."
            post_checksum=$(sha256sum "$file" | awk '{print $1}')
            if [ "$pre_checksum" = "$post_checksum" ]; then
              log "Error: File $file was not modified by Gemini CLI."
              continue
            else
              log "File $file was modified and supposedly resolved."
            fi
          else
            log "Error: Gemini CLI failed while processing $file."
            continue
          fi

          # Verify that conflict markers are gone
          if grep -qE "<<<<<<<|=======|>>>>>>>" "$file"; then
            log "WARNING: Conflict markers still present in $file after Gemini attempt."
          else
            log "Conflict markers successfully removed from $file."
            git add "$file"
          fi
        done

        # Final check for remaining conflicts
        local remaining_conflicts
        remaining_conflicts=$(git diff --name-only --diff-filter=U)
        if [ -n "$remaining_conflicts" ]; then
          log "Error: Unresolved conflicts remain in: $remaining_conflicts. Aborting merge for PR #$number."
          git merge --abort
          post_comment "$number" "❌ Failed to autonomously resolve all conflicts. Remaining: $remaining_conflicts"
          return 0
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
        log "Pushing updated changes to $head_repo ($head_ref)..."
        if git push "$authenticated_head_url" "HEAD:$head_ref"; then
          log "Successfully updated PR #$number and pushed to $head_ref."
          post_comment "$number" "✅ Successfully updated PR #$number with latest changes from $base_ref and resolved any conflicts."

          # Wait a bit for GitHub to re-calculate mergeability after push
          log "Waiting for GitHub to re-calculate mergeability..."
          sleep 15
          mergeable=$(poll_mergeability "$number")
        else
          log "Error: Failed to push updated changes to $head_ref."
          post_comment "$number" "❌ Failed to push updated changes to $head_ref. Please check if the branch is protected."
          return 0
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
    # Get the latest head SHA to check CI status accurately
    local current_head_sha
    current_head_sha=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                            -H "Accept: application/vnd.github.v3+json" \
                            "$API_BASE/pulls/$number" | jq -r '.head.sha')

    if ! check_ci_status "$number" "$current_head_sha"; then
      log "CI check failed or still in progress for PR #$number. Skipping squash-merge."
      return 0
    fi

    approve_pr "$number"
    log "Attempting squash and merge for PR #$number via GitHub API..."
    # Capture HTTP status code and response body
    local merge_output merge_response http_code merged msg
    merge_output=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
                                   -H "Accept: application/vnd.github.v3+json" \
                                   -d "$(jq -n --arg number "$number" '{merge_method: "squash", commit_title: ("chore: squash merge PR #" + $number)}')" \
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

    if [ "$merged" = "true" ] && [ "$http_code" -eq 200 ]; then
      log "SUCCESS: PR #$number has been squash-merged."
      post_comment "$number" "✅ PR #$number has been successfully squash-merged after autonomous verification."
    else
      log "FAILED (HTTP $http_code): Could not merge PR #$number. Reason: $msg"
      log "Full API response: $merge_response"
      post_comment "$number" "❌ Failed to squash-merge PR #$number (HTTP $http_code). Reason: $msg. Full details logged in GitHub Actions."
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

while read -r pr; do
  # Use a subshell to ensure failures in one PR don't stop the script
  ( process_pr "$pr" ) || log "Error occurred while processing PR. Continuing to next PR..."
done < "$PR_LIST_FILE"

log "Finished processing all pull requests."
