#!/bin/bash
# auto_resolve_mrs_gitlab.sh

set -euo pipefail

# Helper function for logging with timestamps
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Global variables for cleanup
ALL_MRS_FILE=""
MR_LIST_FILE=""
PROMPT_FILE=""

cleanup() {
  log "Performing final cleanup of temporary files..."
  rm -f "$ALL_MRS_FILE" "$MR_LIST_FILE" "$PROMPT_FILE"
}
trap cleanup EXIT

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"

# Identify project. Use CI_PROJECT_ID if available.
if [ -z "${CI_PROJECT_ID:-}" ]; then
  if [ -z "${GITLAB_PROJECT_ID:-}" ]; then
    log "Error: Neither CI_PROJECT_ID nor GITLAB_PROJECT_ID is set. Cannot determine GitLab project."
    exit 1
  fi
  PROJECT_ID="$GITLAB_PROJECT_ID"
else
  PROJECT_ID="$CI_PROJECT_ID"
fi

API_BASE="$GITLAB_URL/api/v4/projects/$PROJECT_ID"

log "Target GitLab Project ID: $PROJECT_ID"

if [ -z "${GITLAB_TOKEN:-}" ]; then
  log "Error: GITLAB_TOKEN is not set."
  exit 1
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  log "Error: GEMINI_API_KEY is not set."
  exit 1
fi

# Validate connection with the token
log "Validating GitLab connection and token..."
VALIDATION_RESPONSE=$(curl -s -w "\n%{http_code}" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/user")
HTTP_CODE=$(printf '%s\n' "$VALIDATION_RESPONSE" | tail -n 1)
VALIDATION_BODY=$(printf '%s\n' "$VALIDATION_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -ne 200 ]; then
  log "Error: Failed to validate GitLab token. HTTP Status: $HTTP_CODE"
  log "Response: $VALIDATION_BODY"
  exit 1
fi

USER_NAME=$(printf '%s\n' "$VALIDATION_BODY" | jq -r '.username')
log "Successfully connected to GitLab as user: $USER_NAME"

GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.0-flash}"
log "Using Gemini Model: $GEMINI_MODEL"

# Check for required tools
for tool in jq gemini curl git file sha256sum; do
  if ! command -v "$tool" &> /dev/null; then
    log "Error: $tool is not installed or not in PATH."
    exit 1
  fi
done

# Configure git
git config user.name "gitlab-ci[bot]"
git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"

# Fetch all remotes and branches to ensure we have context
log "Fetching all branches..."
git fetch --all

# Function to post a comment to an MR
post_comment() {
  local mr_iid=$1
  local body=$2
  log "Posting comment to MR !$mr_iid..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
       -H "Content-Type: application/json" \
       -d "$(jq -n --arg body "$body" '{body: $body}')" \
       "$API_BASE/merge_requests/$mr_iid/notes")
  if [ "$http_code" -ne 201 ]; then
    log "Warning: Failed to post comment to MR !$mr_iid (HTTP $http_code)"
  fi
}

# 1. Fetch all open merge requests (handling pagination)
log "Step 1: Fetching all open merge requests for project $PROJECT_ID..."
page=1
ALL_MRS_FILE=$(mktemp)
echo "[]" > "$ALL_MRS_FILE"

while : ; do
  log "Fetching page $page of MRs..."
  mrs_page=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                    "$API_BASE/merge_requests?state=opened&per_page=100&page=$page&order_by=created_at&sort=asc")

  # Check if we got an error message instead of an array
  if printf '%s\n' "$mrs_page" | jq -e '.message' >/dev/null 2>&1; then
    log "Error from GitLab API: $(printf '%s\n' "$mrs_page" | jq -r '.message')"
    exit 1
  fi

  count=$(printf '%s\n' "$mrs_page" | jq '. | length')
  if [ "$count" -eq 0 ]; then
    break
  fi

  # Merge current page into total list
  temp_all_mrs=$(mktemp)
  if jq -s 'add' "$ALL_MRS_FILE" <(printf '%s\n' "$mrs_page") > "$temp_all_mrs"; then
    mv "$temp_all_mrs" "$ALL_MRS_FILE"
  else
    log "Error: Failed to process MR JSON on page $page."
    rm -f "$temp_all_mrs"
    exit 1
  fi

  page=$((page+1))
done

total_count=$(jq '. | length' "$ALL_MRS_FILE")
log "Found $total_count open merge requests in total."

# Function to process a single MR
process_mr() {
  local mr="$1"
  local iid source_branch target_branch draft mr_title mr_desc has_conflicts merge_status source_project_id

  iid=$(printf '%s\n' "$mr" | jq -r '.iid')
  source_branch=$(printf '%s\n' "$mr" | jq -r '.source_branch')
  target_branch=$(printf '%s\n' "$mr" | jq -r '.target_branch')
  draft=$(printf '%s\n' "$mr" | jq -r '.draft')
  mr_title=$(printf '%s\n' "$mr" | jq -r '.title')
  mr_desc=$(printf '%s\n' "$mr" | jq -r '.description // ""')
  has_conflicts=$(printf '%s\n' "$mr" | jq -r '.has_conflicts')
  merge_status=$(printf '%s\n' "$mr" | jq -r '.merge_status')
  source_project_id=$(printf '%s\n' "$mr" | jq -r '.source_project_id')

  log ""
  log "=== Processing MR !$iid ($source_branch -> $target_branch) ==="

  if [ "$draft" = "true" ]; then
    log "MR !$iid is a draft. Skipping."
    return 0
  fi

  # Ensure a clean state for each iteration
  git reset --hard HEAD
  git clean -fd

  # Extract the clone URL for the source project
  local source_project_info source_clone_url authenticated_source_url
  source_project_info=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$source_project_id")
  source_clone_url=$(printf '%s\n' "$source_project_info" | jq -r '.http_url_to_repo')

  if [ "$source_clone_url" = "null" ] || [ -z "$source_clone_url" ]; then
     log "Error: Failed to fetch source clone URL for project $source_project_id."
     return 0
  fi

  # Use token in URL for fork pushing
  # GitLab URL structure: https://oauth2:TOKEN@gitlab.com/...
  authenticated_source_url=$(printf '%s\n' "$source_clone_url" | sed "s|https://|https://oauth2:${GITLAB_TOKEN}@|")

  # Fetch the MR branch
  log "Fetching $source_branch from source project..."
  if ! git fetch "$authenticated_source_url" "$source_branch"; then
    log "Error: Failed to fetch MR branch."
    return 0
  fi
  local mr_head_commit
  mr_head_commit=$(git rev-parse FETCH_HEAD)

  # Fetch the target branch
  log "Fetching origin/$target_branch..."
  if ! git fetch origin "$target_branch"; then
    log "Error: Failed to fetch target branch origin/$target_branch."
    return 0
  fi

  # Check if MR is behind target
  local behind_count
  behind_count=$(git rev-list --count "$mr_head_commit..origin/$target_branch")

  if [ "$has_conflicts" = "true" ] || [ "$behind_count" -gt 0 ]; then
    log "MR !$iid needs update (conflicted: $has_conflicts, behind: $behind_count)."

    log "Attempting automated update/resolution for MR !$iid..."

    # Use a unique local branch name to avoid collisions
    local local_branch="auto-resolve-mr-$iid"
    log "Checking out local branch $local_branch from $mr_head_commit..."
    git checkout -B "$local_branch" "$mr_head_commit"

    log "Attempting to merge origin/$target_branch into $local_branch..."
    if ! git merge "origin/$target_branch" --no-edit; then
      log "Merge failed with conflicts. Identifying files..."
      local conflicts
      conflicts=$(git diff --name-only --diff-filter=U)

      post_comment "$iid" "🤖 MR !$iid has conflicts. Attempting autonomous resolution via Gemini CLI ($GEMINI_MODEL)..."

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
        PROMPT_FILE=$(mktemp)
        {
          printf "You are an autonomous AI engineer working in a GitLab CI environment.\n"
          printf "Your task is to resolve git merge conflicts in the file '%s' for Merge Request !%s.\n\n" "$file" "$iid"
          printf "### CONTEXT\n"
          printf "MR Title: %s\n" "$mr_title"
          printf "MR Description: %s\n\n" "$mr_desc"
          printf "### OBJECTIVE\n"
          printf "Use your tools to:\n"
          printf "1. Read the file '%s' to identify the conflict markers (<<<<<<<, =======, >>>>>>>).\n" "$file"
          printf "2. Resolve the conflicts accurately, preserving intended logic from both branches where appropriate.\n"
          printf "3. MANDATORY: Write the fully resolved, clean content back to '%s' using your file-writing tools. You must overwrite the file with the resolved version.\n" "$file"
          printf "4. Ensure NO conflict markers (<<<<<<<, =======, >>>>>>>) remain in the file.\n"
          printf "5. MANDATORY: Verify the resulting code is syntactically correct by running a syntax check if a tool is available.\n"
          printf "6. Ensure the resulting code is functional and preserves the intended logic.\n"
          printf "7. Use your tools like 'ls -R', 'find', or 'grep' to explore the repository if you need to understand imports, dependencies, or context in other files.\n"
          printf "8. If the conflict is in a configuration file (like package.json), ensure the resulting JSON is valid.\n\n"
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
        log "Error: Unresolved conflicts remain in: $remaining_conflicts. Aborting merge for MR !$iid."
        git merge --abort
        post_comment "$iid" "❌ Failed to autonomously resolve all conflicts. Remaining: $remaining_conflicts"
        return 0
      fi

      if [ -n "$(git status --short)" ]; then
        log "Committing resolved conflicts for MR !$iid..."
        git commit -m "chore: auto-resolve merge conflicts for MR !$iid via gemini-cli"
      else
        log "No changes to commit after conflict resolution attempt."
      fi
    else
      log "Merge was successful (no conflicts found)."
    fi

    # Check if we have new commits to push
    if [ $(git rev-list --count "$mr_head_commit..HEAD") -gt 0 ]; then
      log "Pushing updated changes to source branch ($source_branch)..."
      if git push "$authenticated_source_url" "HEAD:$source_branch"; then
        log "Successfully updated MR !$iid and pushed to $source_branch."
        post_comment "$iid" "✅ Successfully updated MR !$iid with latest changes from $target_branch and resolved any conflicts."

        # Wait a bit for GitLab to re-calculate mergeability
        log "Waiting for GitLab to re-calculate mergeability..."
        sleep 15

        # Refresh MR info
        mr=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API_BASE/merge_requests/$iid")
        merge_status=$(printf '%s\n' "$mr" | jq -r '.merge_status')
      else
        log "Error: Failed to push updated changes to $source_branch."
        post_comment "$iid" "❌ Failed to push updated changes to $source_branch. Please check if the branch is protected."
        return 0
      fi
    else
      log "No changes to commit or push for MR !$iid."
    fi
  elif [ "$merge_status" = "can_be_merged" ]; then
    log "MR !$iid is mergeable and up to date."
  fi

  # 3. Squash and Merge
  if [ "$merge_status" = "can_be_merged" ]; then
    log "Attempting squash and merge for MR !$iid via GitLab API..."
    local merge_output merge_response http_code merged msg
    merge_output=$(curl -s -w "\n%{http_code}" -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                                   -H "Content-Type: application/json" \
                                   -d '{"squash":true, "should_remove_source_branch": true}' \
                                   "$API_BASE/merge_requests/$iid/merge")

    merge_response=$(printf '%s\n' "$merge_output" | head -n -1)
    http_code=$(printf '%s\n' "$merge_output" | tail -n 1)

    if [ "$http_code" -eq 200 ]; then
      log "SUCCESS: MR !$iid has been squash-merged."
      post_comment "$iid" "✅ MR !$iid has been successfully squash-merged after autonomous verification."
    else
      msg=$(printf '%s\n' "$merge_response" | jq -r 'if .message == null then "Unknown error" else .message end' 2>/dev/null || printf "Unknown error")
      log "FAILED (HTTP $http_code): Could not merge MR !$iid. Reason: $msg"
      post_comment "$iid" "❌ Failed to squash-merge MR !$iid (HTTP $http_code). Reason: $msg"
    fi
  else
    log "MR !$iid is not mergeable ($merge_status). Skipping merge."
  fi

  # Return to target branch (clean up)
  git checkout "$target_branch" || true
}

# Loop through each MR using a temporary file to avoid subshell issues with pipe
log "Step 2: Processing merge requests one by one..."
MR_LIST_FILE=$(mktemp)
jq -c '.[]' "$ALL_MRS_FILE" > "$MR_LIST_FILE"

while read -r mr; do
  ( process_mr "$mr" ) || log "Error occurred while processing MR. Continuing to next MR..."
done < "$MR_LIST_FILE"

log "Finished processing all merge requests."
