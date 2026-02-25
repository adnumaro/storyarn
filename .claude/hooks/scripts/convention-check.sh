#!/usr/bin/env bash
# PostToolUse hook: Check Storyarn conventions on newly written code.
# Only analyzes the NEW code from Edit (new_string) or Write (content).
# Supports inline suppression: # storyarn:disable or # storyarn:disable:rule_name
# Block suppression: # storyarn:disable-start / # storyarn:disable-end

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check Elixir files
[[ "$FILE_PATH" == *.ex ]] || [[ "$FILE_PATH" == *.exs ]] || exit 0

# Get the new code (Edit → new_string, Write → content)
NEW_CODE=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
[[ -n "$NEW_CODE" ]] || exit 0

# Shared convention engine
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/convention-rules.sh"

check_conventions "$NEW_CODE" "$FILE_PATH" "hook"
