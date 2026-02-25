#!/usr/bin/env bash
# PostToolUse hook: Log file modifications to active progress file
FILE_PATH=$(cat | jq -r '.tool_input.file_path // empty')
if [[ -n "$FILE_PATH" ]]; then
  LATEST=$(ls -t .claude/plans/*/progress.md 2>/dev/null | head -1)
  if [[ -n "$LATEST" ]]; then
    echo "[$(date '+%H:%M')] Modified: $FILE_PATH" >> "$LATEST"
  fi
fi
