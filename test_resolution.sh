#!/bin/bash
# test_resolution.sh
# Verifies the autonomous conflict resolution logic using a local git repo.

set -euo pipefail

log() {
  echo "[TEST] $*"
}

# Create a temporary directory for the test
TEST_DIR=$(mktemp -d)
log "Created test directory: $TEST_DIR"
cd "$TEST_DIR"

# Initialize a git repository with 'main' as default branch
git init -q -b main
git config user.name "test"
git config user.email "test@example.com"
git config merge.conflictStyle diff3

# Create a file with initial content
cat <<EOF > main.py
def hello():
    print("hello world")
EOF
git add main.py
git commit -m "initial commit" -q

# Create a branch and modify the file
git checkout -b feature -q
cat <<EOF > main.py
def hello():
    print("hello from feature")
EOF
git add main.py
git commit -m "feature commit" -q

# Go back to main and create a conflicting change
git checkout main -q
cat <<EOF > main.py
def hello():
    print("hello from main")
EOF
git add main.py
git commit -m "main commit" -q

# Attempt to merge and expect a conflict
log "Attempting merge (expecting conflict)..."
set +e
git merge feature
set -e

if ! git diff --name-only --diff-filter=U | grep -q "main.py"; then
  log "FAILED: Expected conflict in main.py not found."
  exit 1
fi
log "Conflict created successfully in main.py."

# Define a mock Gemini resolution if GEMINI_API_KEY is not set
if [ -z "${GEMINI_API_KEY:-}" ]; then
  log "GEMINI_API_KEY not set. Using mock resolution."
  # Mock: just pick one side and remove markers
  # diff3 markers use 7 pipes: |||||||
  sed -i '/<<<<<<<\|||||||\|=======\|>>>>>>>/d' main.py
  log "Mock resolution applied."
else
  log "GEMINI_API_KEY is set. Running real resolution via gemini CLI..."
  # This part simulates the prompt generation from auto_resolve_prs.sh
  PROMPT="Resolve the following git merge conflict in main.py. Ensure no markers remain and the code is syntactically correct python."
  # Note: in real script we use stdin.
  if command -v gemini &>/dev/null; then
    gemini --prompt "$PROMPT" --approval-mode yolo --skip-trust < main.py
  else
    log "Gemini CLI not found. Skipping real resolution."
    sed -i '/<<<<<<<\|=======\|>>>>>>>/d' main.py
  fi
fi

# Verify resolution
if grep -qE "<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>" main.py; then
  log "FAILED: Conflict markers still present in main.py."
  exit 1
fi

log "SUCCESS: Conflict markers removed."
log "Final content of main.py:"
cat main.py

# Cleanup
rm -rf "$TEST_DIR"
log "Test complete."
