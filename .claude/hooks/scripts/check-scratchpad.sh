#!/usr/bin/env bash
# SessionStart hook: Notify if scratchpad files exist from previous sessions
COUNT=$(ls .claude/plans/*/scratchpad.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$COUNT" -gt 0 ]]; then
  LATEST=$(ls -t .claude/plans/*/scratchpad.md 2>/dev/null | head -1)
  echo "Scratchpad: $COUNT note(s) found — latest: $LATEST"
fi
