#!/bin/bash
# Securely provisions the Intelephense Premium license key for AI agents.
# Ensure the INTELEPHENSE_LICENCE_KEY environment variable is set before running.

if [ -z "$INTELEPHENSE_LICENCE_KEY" ]; then
    echo "Error: INTELEPHENSE_LICENCE_KEY environment variable is not set."
    echo "Please set it using: export INTELEPHENSE_LICENCE_KEY='your_key'"
else
    mkdir -p "$HOME/intelephense"
    echo "$INTELEPHENSE_LICENCE_KEY" > "$HOME/intelephense/licence.txt"
    echo "Intelephense Premium license key provisioned to $HOME/intelephense/licence.txt"
fi
