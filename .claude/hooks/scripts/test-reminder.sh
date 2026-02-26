#!/usr/bin/env bash
# PostToolUse hook: Remind to create tests for new modules.
# Only triggers on Write (new file creation) for lib/ Elixir files.
# Non-blocking — outputs a reminder, always exits 0.

set -euo pipefail

INPUT=$(cat)

# Only check Write operations (new files / full rewrites)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" == "Write" ]] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check lib/ Elixir files
[[ "$FILE_PATH" == *.ex ]] || exit 0
echo "$FILE_PATH" | grep -q '/lib/' || exit 0

# Skip files that don't need dedicated tests
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  application.ex|repo.ex|mailer.ex|endpoint.ex|router.ex|telemetry.ex|gettext.ex)
    exit 0
    ;;
  storyarn.ex|storyarn_web.ex)
    exit 0
    ;;
esac

# Skip schema-only files (schemas are tested via their CRUD module tests)
# Skip migration files
echo "$FILE_PATH" | grep -q '/priv/repo/migrations/' && exit 0

# Derive expected test path: lib/foo/bar.ex → test/foo/bar_test.exs
TEST_PATH=$(echo "$FILE_PATH" | sed 's|/lib/|/test/|' | sed 's|\.ex$|_test.exs|')

# Check if test file exists
if [[ ! -f "$TEST_PATH" ]]; then
  echo "TEST REMINDER: No test file found for this module."
  echo "  Source:   $FILE_PATH"
  echo "  Expected: $TEST_PATH"
fi

exit 0
