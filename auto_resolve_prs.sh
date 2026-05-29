#!/bin/bash
# auto_resolve_prs.sh

set -euo pipefail

# Use GITHUB_REPOSITORY if available, otherwise fallback to the current repo
REPO="${GITHUB_REPOSITORY:-8bukets/MapAntigravity}"
API_BASE="https://api.github.com/repos/$REPO"

# Helper function for logging with timestamps
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

if [ -z "$GITHUB_TOKEN" ]; then
  log "Error: GITHUB_TOKEN is not set."
  exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
  log "Error: GEMINI_API_KEY is not set."
  exit 1
fi

# Check for required tools
if ! command -v jq &> /dev/null; then
    log "Error: jq is not installed or not in PATH."
    exit 1
fi

if ! command -v gemini &> /dev/null; then
    log "Error: gemini is not installed or not in PATH."
    exit 1
fi

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Fetch all remotes and branches to ensure we have context
log "Fetching all branches..."
git fetch --all

# Function to poll mergeability
poll_mergeability() {
  local pr_number=$1
  local status="null"
  local attempts=0
  local max_attempts=10

  while [ "$status" = "null" ] && [ $attempts -lt $max_attempts ]; do
    pr_detail=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                         -H "Accept: application/vnd.github.v3+json" \
                         "$API_BASE/pulls/$pr_number")
    status=$(echo "$pr_detail" | jq -r '.mergeable')
    if [ "$status" = "null" ]; then
      log "Mergeability status for PR #$pr_number is null (calculating). Waiting..."
      sleep 10
      attempts=$((attempts+1))
    fi
  done
  echo "$status"
}

# 1. Fetch all open pull requests (handling pagination)
log "Fetching all open pull requests for $REPO..."
page=1
all_prs="[]"
while : ; do
  prs_page=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "$API_BASE/pulls?state=open&per_page=100&page=$page&sort=created&direction=asc")

  # Check if we got an error message instead of an array
  if echo "$prs_page" | jq -e '.message' >/dev/null 2>&1; then
    log "Error from GitHub API: $(echo "$prs_page" | jq -r '.message')"
    exit 1
  fi

  count=$(echo "$prs_page" | jq '. | length')
  if [ "$count" -eq 0 ]; then
    break
  fi

  all_prs=$(echo "$all_prs" "$prs_page" | jq -s 'add')
  page=$((page+1))
done

total_count=$(echo "$all_prs" | jq '. | length')
log "Found $total_count open pull requests."

# Loop through each PR
echo "$all_prs" | jq -c '.[]' | while read -r pr; do
  # Use a subshell to ensure failures in one PR don't stop the script
  (
  number=$(echo "$pr" | jq -r '.number')
  head_ref=$(echo "$pr" | jq -r '.head.ref')
  base_ref=$(echo "$pr" | jq -r '.base.ref')
  head_repo=$(echo "$pr" | jq -r '.head.repo.full_name')
  is_draft=$(echo "$pr" | jq -r '.draft')
  pr_title=$(echo "$pr" | jq -r '.title')
  pr_body=$(echo "$pr" | jq -r '.body')

  log ""
  log "=== Processing PR #$number ($head_ref -> $base_ref) ==="

  if [ "$is_draft" = "true" ]; then
    log "PR #$number is a draft. Skipping."
    continue
  fi

  # Ensure a clean state for each iteration
  git reset --hard HEAD
  git clean -fd

  # Avoid messing with forks if permissions are restricted
  if [ "$head_repo" != "$REPO" ]; then
    log "PR #$number is from a fork ($head_repo). Skipping to avoid potential permission issues with GITHUB_TOKEN."
    continue
  fi

  # 2. Check mergeability
  mergeable=$(poll_mergeability "$number")

  if [ "$mergeable" = "false" ]; then
    log "PR #$number has conflicts. Attempting autonomous resolution via Gemini CLI..."

    # Fetch and checkout the PR branch explicitly
    git fetch origin "$head_ref"
    git checkout -B "$head_ref" "origin/$head_ref"

    # Ensure we have the latest base branch
    git fetch origin "$base_ref"

    # Attempt to merge the base branch into the head branch
    log "Attempting to merge origin/$base_ref into $head_ref..."
    if ! git merge "origin/$base_ref" --no-edit; then
      log "Merge failed with conflicts. Identifying files..."
      conflicts=$(git diff --name-only --diff-filter=U)

      for file in $conflicts; do
        log "Resolving conflicts in $file..."
        # Use gemini-cli to resolve conflicts autonomously
        # We use --yolo and --skip-trust as requested for autonomous automatic resolution

        # PROMPT GENERATION (Hardened against injection from PR metadata)
        # We use a temporary file to construct the prompt and pass it via stdin.
        {
          printf "You are an autonomous AI engineer working in a GitHub Actions CI environment.\n"
          printf "Your task is to resolve git merge conflicts in the file '%s' for Pull Request #%s.\n\n" "$file" "$number"
          printf "### CONTEXT\n"
          printf "PR Title: %s\n" "$pr_title"
          printf "PR Description: %s\n\n" "$pr_body"
          printf "### OBJECTIVE\n"
          printf "Use your tools to:\n"
          printf "1. Read the file '%s' to identify the conflict markers (<<<<<<<, =======, >>>>>>>).\n" "$file"
          printf "2. Resolve the conflicts accurately, preserving intended logic from both branches where appropriate.\n"
          printf "3. Write the fully resolved, clean content back to '%s' using your file-writing tools.\n" "$file"
          printf "4. Ensure NO conflict markers remain in the file.\n"
          printf "5. Ensure the resulting code is syntactically correct and functional.\n\n"
          printf "Do not provide any conversational response or explanation. Focus entirely on using your tools to resolve the conflicts in '%s'.\n" "$file"
        } > .gemini_prompt.txt
        # We pass the prompt via stdin and use --prompt "" to trigger headless mode safely
        log "Invoking Gemini CLI for $file..."
        if cat .gemini_prompt.txt | gemini --prompt "" --yolo --approval-mode yolo --skip-trust; then
          log "Gemini CLI finished processing $file."
        else
          log "Error: Gemini CLI failed while processing $file."
        fi
        rm .gemini_prompt.txt

        # Verify that conflict markers are gone
        if grep -qE "<<<<<<<|=======|>>>>>>>" "$file"; then
          log "WARNING: Conflict markers still present in $file after Gemini attempt. Skipping this file."
        else
          log "Conflict markers successfully removed from $file."
          git add "$file"
        fi
      done

      if [ -n "$(git status --short)" ]; then
        git commit -m "chore: auto-resolve merge conflicts via gemini-cli"
      fi

      if [ $(git rev-list --count "origin/$head_ref..$head_ref") -gt 0 ]; then
        git push origin "$head_ref"
        log "Resolved conflicts and pushed to $head_ref."

        # Wait a bit for GitHub to re-calculate mergeability after push
        log "Waiting for GitHub to re-calculate mergeability..."
        sleep 15
        mergeable=$(poll_mergeability "$number")
      else
        log "No changes to commit or push after resolution attempt."
      fi
    else
      log "Merge was successful (no conflicts found upon local merge attempt)."
      if [ $(git rev-list --count "origin/$head_ref..$head_ref") -gt 0 ]; then
         git push origin "$head_ref"
         log "Waiting for GitHub to re-calculate mergeability..."
         sleep 15
         mergeable=$(poll_mergeability "$number")
      fi
    fi
  elif [ "$mergeable" = "true" ]; then
    log "PR #$number is mergeable."
  else
    log "PR #$number mergeability is unknown or still calculating ($mergeable). Skipping resolution."
  fi

  # 3. Squash and Merge
  if [ "$mergeable" = "true" ]; then
    log "Attempting squash and merge for PR #$number..."
    merge_response=$(curl -s -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
                                   -H "Accept: application/vnd.github.v3+json" \
                                   -d '{"merge_method":"squash"}' \
                                   "$API_BASE/pulls/$number/merge")

    merged=$(echo "$merge_response" | jq -r '.merged // false')
    if [ "$merged" = "true" ]; then
      log "SUCCESS: PR #$number has been squash-merged."
    else
      msg=$(echo "$merge_response" | jq -r '.message // "Unknown error"')
      log "FAILED: Could not merge PR #$number. Reason: $msg"
    fi
  else
    log "PR #$number is not mergeable ($mergeable). Skipping merge."
  fi

  # Return to default branch for next iteration
  git checkout "$base_ref" || true
  ) || log "Error occurred while processing PR. Continuing to next PR..."
done
