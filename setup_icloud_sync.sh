#!/bin/bash

# ==============================================================================
# ANTIGRAVITY ICLOUD SYNCHRONIZATION SETUP
# This script moves the Antigravity App Data Directory (containing all conversation 
# histories, brain logs, artifacts, and tasks) to your iCloud Drive, and sets up 
# a transparent symbolic link so that all future agent savings are done directly in iCloud.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Define Paths
LOCAL_DIR="$HOME/.gemini/antigravity"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/antigravity"
BACKUP_DIR="$HOME/.gemini/antigravity_backup_$(date +%Y%m%d_%H%M%S)"

echo "=================================================="
echo "🍏 Setting up iCloud Sync for Antigravity Brain & Savings 🍏"
echo "=================================================="
echo ""

# 1. Verify Local App Data Directory exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo "❌ Error: Antigravity directory not found at $LOCAL_DIR"
    echo "Please ensure the Antigravity Desktop app is installed and has run at least once."
    exit 1
fi

# 2. Create the target folder in iCloud
echo "Step 1: Creating 'antigravity' folder in iCloud Drive..."
mkdir -p "$ICLOUD_DIR"
echo "✓ iCloud folder ready at: $ICLOUD_DIR"
echo ""

# 3. Synchronize current data to iCloud
echo "Step 2: Syncing all your current savings, brain data, and logs to iCloud..."
# Using rsync to preserve permissions, times, and copy recursively
rsync -av --progress "$LOCAL_DIR/" "$ICLOUD_DIR/"
echo "✓ Sync complete! All current data is now in iCloud."
echo ""

# 4. Backup the local directory
echo "Step 3: Creating a safe local backup..."
mv "$LOCAL_DIR" "$BACKUP_DIR"
echo "✓ Local backup created at: $BACKUP_DIR"
echo ""

# 5. Create the Symbolic Link
echo "Step 4: Creating symlink to iCloud..."
ln -s "$ICLOUD_DIR" "$LOCAL_DIR"
echo "✓ Symlink created: $LOCAL_DIR -> $ICLOUD_DIR"
echo ""

echo "=================================================="
echo "🎉 SUCCESS! Antigravity is now fully synced with iCloud! 🎉"
echo "All your active conversation logs, artifacts, and"
echo "brains are stored and backed up safely in iCloud."
echo "=================================================="
echo ""
echo "Note: You can safely delete the local backup at:"
echo "      $BACKUP_DIR"
echo "after verifying that the application is running normally."
