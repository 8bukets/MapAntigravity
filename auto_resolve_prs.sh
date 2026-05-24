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

# 1. Fetch open pull requests
echo "Fetching open pull requests for $REPO..."
prs=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
               -H "Accept: application/vnd.github.v3+json" \
               "$API_BASE/pulls?state=open")

# Check if we got an error message instead of an array
if echo "$prs" | jq -e '.message' >/dev/null 2>&1; then
  echo "Error from GitHub API: $(echo "$prs" | jq -r '.message')"
  exit 1
fi

count=$(echo "$prs" | jq '. | length')
echo "Found $count open pull requests."

# Loop through each PR
echo "$prs" | jq -c '.[]' | while read -r pr; do
  number=$(echo "$pr" | jq -r '.number')
  head_ref=$(echo "$pr" | jq -r '.head.ref')
  base_ref=$(echo "$pr" | jq -r '.base.ref')
  head_repo=$(echo "$pr" | jq -r '.head.repo.full_name')

  echo ""
  echo "=== Processing PR #$number ($head_ref -> $base_ref) ==="

  # Avoid messing with forks if permissions are restricted
  if [ "$head_repo" != "$REPO" ]; then
    echo "PR #$number is from a fork ($head_repo). Skipping to avoid potential permission issues with GITHUB_TOKEN."
    continue
  fi

  # 2. Check mergeability with polling for 'null' status
  mergeable="null"
  attempts=0
  max_attempts=5
  while [ "$mergeable" = "null" ] && [ $attempts -lt $max_attempts ]; do
    pr_detail=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                         -H "Accept: application/vnd.github.v3+json" \
                         "$API_BASE/pulls/$number")
    mergeable=$(echo "$pr_detail" | jq -r '.mergeable')
    if [ "$mergeable" = "null" ]; then
      echo "Mergeability status is null (calculating). Waiting..."
      sleep 5
      attempts=$((attempts+1))
    fi
  done

  if [ "$mergeable" = "false" ]; then
    echo "PR #$number has conflicts. Attempting autonomous resolution via Gemini CLI..."

    # Fetch and checkout the PR branch
    git fetch origin "$head_ref"
    git checkout "$head_ref"

    # Attempt to merge the base branch into the head branch
    if ! git merge "origin/$base_ref" --no-edit; then
      echo "Merge failed with conflicts. Identifying files..."
      conflicts=$(git diff --name-only --diff-filter=U)

      for file in $conflicts; do
        echo "Resolving conflicts in $file..."
        # Use gemini-cli to resolve conflicts autonomously
        # We tell it specifically to use its file tools.
        gemini -p "The file '$file' has git merge conflicts. Use your tools to read the file, resolve the conflicts accurately while preserving all intended logic from both sides where appropriate, and write the resolved content back to the file." --yolo --approval-mode yolo
        git add "$file"
      done

      if [ -n "$(git status --short)" ]; then
        git commit -m "chore: auto-resolve merge conflicts via gemini-cli"
        git push origin "$head_ref"
        echo "Resolved conflicts and pushed to $head_ref."
      else
        echo "No changes to commit after resolution attempt."
      fi
    else
      echo "Merge was successful (no conflicts found upon local merge attempt)."
      if [ -n "$(git status --short)" ]; then
         git push origin "$head_ref"
      fi
    fi
  elif [ "$mergeable" = "true" ]; then
    echo "PR #$number is mergeable."
  else
    echo "PR #$number mergeability is unknown or still calculating ($mergeable). Skipping resolution."
  fi

  # 3. Squash and Merge
  # Re-verify mergeable status before merging
  pr_detail=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$API_BASE/pulls/$number")
  mergeable=$(echo "$pr_detail" | jq -r '.mergeable')

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
  # We use the current branch we started with or base_ref
  git checkout "$base_ref"
done
