#!/usr/bin/env bash
# SessionStart hook: Create core workflow directories (other dirs created by skills on demand)
mkdir -p .claude/plans .claude/reviews .claude/solutions .claude/audit 2>/dev/null || true
