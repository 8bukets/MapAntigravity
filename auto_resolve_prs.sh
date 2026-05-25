#!/bin/bash
# auto_resolve_prs.sh

set -e

# Use GITHUB_REPOSITORY if available, otherwise fallback to the current repo
REPO="${GITHUB_REPOSITORY:-8bukets/MapAntigravity}"
API_BASE="https://api.github.com/repos/$REPO"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
  echo "Error: GEMINI_API_KEY is not set."
  exit 1
fi

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Fetch all remotes and branches to ensure we have context
echo "Fetching all branches..."
git fetch --all

# Function to poll mergeability
poll_mergeability() {
  local pr_number=$1
  local status="null"
  local attempts=0
  local max_attempts=10

  while [ "$status" = "null" ] && [ $attempts -lt $max_attempts ]; do
    pr_detail=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                         -H "Accept: application/vnd.github.v3+json" \
                         "$API_BASE/pulls/$pr_number")
    status=$(echo "$pr_detail" | jq -r '.mergeable')
    if [ "$status" = "null" ]; then
      echo "Mergeability status for PR #$pr_number is null (calculating). Waiting..."
      sleep 10
      attempts=$((attempts+1))
    fi
  done
  echo "$status"
}

# 1. Fetch all open pull requests (handling pagination)
echo "Fetching all open pull requests for $REPO..."
page=1
all_prs="[]"
while : ; do
  prs_page=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "$API_BASE/pulls?state=open&per_page=100&page=$page")

  # Check if we got an error message instead of an array
  if echo "$prs_page" | jq -e '.message' >/dev/null 2>&1; then
    echo "Error from GitHub API: $(echo "$prs_page" | jq -r '.message')"
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
echo "Found $total_count open pull requests."

# Loop through each PR
echo "$all_prs" | jq -c '.[]' | while read -r pr; do
  number=$(echo "$pr" | jq -r '.number')
  head_ref=$(echo "$pr" | jq -r '.head.ref')
  base_ref=$(echo "$pr" | jq -r '.base.ref')
  head_repo=$(echo "$pr" | jq -r '.head.repo.full_name')

  echo ""
  echo "=== Processing PR #$number ($head_ref -> $base_ref) ==="

  # Ensure a clean state for each iteration
  git reset --hard HEAD
  git clean -fd

  # Avoid messing with forks if permissions are restricted
  if [ "$head_repo" != "$REPO" ]; then
    echo "PR #$number is from a fork ($head_repo). Skipping to avoid potential permission issues with GITHUB_TOKEN."
    continue
  fi

  # 2. Check mergeability
  mergeable=$(poll_mergeability "$number")

  if [ "$mergeable" = "false" ]; then
    echo "PR #$number has conflicts. Attempting autonomous resolution via Gemini CLI..."

    # Fetch and checkout the PR branch explicitly
    git fetch origin "$head_ref"
    git checkout -B "$head_ref" "origin/$head_ref"

    # Ensure we have the latest base branch
    git fetch origin "$base_ref"

    # Attempt to merge the base branch into the head branch
    echo "Attempting to merge origin/$base_ref into $head_ref..."
    if ! git merge "origin/$base_ref" --no-edit; then
      echo "Merge failed with conflicts. Identifying files..."
      conflicts=$(git diff --name-only --diff-filter=U)

      for file in $conflicts; do
        echo "Resolving conflicts in $file..."
        # Use gemini-cli to resolve conflicts autonomously
        # We use --yolo and --skip-trust as requested for autonomous automatic resolution
        gemini -p "The file '$file' has git merge conflicts. Use your tools to read the file, resolve the conflicts accurately while preserving all intended logic from both sides where appropriate, and write the resolved content back to the file." --yolo --approval-mode yolo --skip-trust
        git add "$file"
      done

      if [ -n "$(git status --short)" ]; then
        git commit -m "chore: auto-resolve merge conflicts via gemini-cli"
        git push origin "$head_ref"
        echo "Resolved conflicts and pushed to $head_ref."

        # Wait a bit for GitHub to re-calculate mergeability after push
        echo "Waiting for GitHub to re-calculate mergeability..."
        sleep 15
        mergeable=$(poll_mergeability "$number")
      else
        echo "No changes to commit after resolution attempt."
      fi
    else
      echo "Merge was successful (no conflicts found upon local merge attempt)."
      if [ -n "$(git status --short)" ]; then
         git push origin "$head_ref"
         echo "Waiting for GitHub to re-calculate mergeability..."
         sleep 15
         mergeable=$(poll_mergeability "$number")
      fi
    fi
  elif [ "$mergeable" = "true" ]; then
    echo "PR #$number is mergeable."
  else
    echo "PR #$number mergeability is unknown or still calculating ($mergeable). Skipping resolution."
  fi

  # 3. Squash and Merge
  if [ "$mergeable" = "true" ]; then
    echo "Attempting squash and merge for PR #$number..."
    merge_response=$(curl -s -X PUT -H "Authorization: token $GITHUB_TOKEN" \
                                   -H "Accept: application/vnd.github.v3+json" \
                                   -d '{"merge_method":"squash"}' \
                                   "$API_BASE/pulls/$number/merge")

    merged=$(echo "$merge_response" | jq -r '.merged // false')
    if [ "$merged" = "true" ]; then
      echo "SUCCESS: PR #$number has been squash-merged."
    else
      msg=$(echo "$merge_response" | jq -r '.message // "Unknown error"')
      echo "FAILED: Could not merge PR #$number. Reason: $msg"
    fi
  else
    echo "PR #$number is not mergeable ($mergeable). Skipping merge."
  fi

  # Return to default branch for next iteration
  git checkout "$base_ref" || true
done
