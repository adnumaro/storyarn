#!/usr/bin/env bash
# PostToolUse hook: after Claude writes a Vue/TS file under assets/app/,
# scan for files with similar suffix names (Panel, Picker, Toolbar,
# Sidebar, Modal, Dialog, Tab, Editor, Builder, Dock, Tree). If 1+
# matches exist, surface them so Claude must re-confirm it didn't
# duplicate an existing pattern.
#
# Goal: catch "I just shipped FlowSequenceConfigPanel.vue while 10 other
# *Panel.vue files already existed" right at the moment of writing.
#
# Output protocol: JSON on stdout with hookSpecificOutput.additionalContext
# so the audit lands in the next-turn context.

set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_response.filePath // .tool_input.file_path // ""')
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

[[ -z "$FILE" ]] && exit 0

# Only audit Vue/TS under assets/app/.
[[ "$FILE" =~ ^${ROOT}/assets/app/.*\.(vue|ts)$ ]] || exit 0

BASENAME=$(basename "$FILE")
NAME="${BASENAME%.*}"

# Detect a "pattern suffix" in the name. First match wins; ordering
# matters because some names like "FlowSequenceConfigPanel" contain both
# "Sequence" and "Panel" — we want the architectural pattern (Panel) not
# the domain noun.
SUFFIX=""
for s in Panel Picker Toolbar Sidebar Modal Dialog Tab Editor Builder Dock Tree Component; do
  if echo "$NAME" | grep -q "$s"; then
    SUFFIX="$s"
    break
  fi
done

[[ -z "$SUFFIX" ]] && exit 0

# Collect near-twins. Exclude the file itself.
MATCHES=$(find "$ROOT/assets/app" -name "*${SUFFIX}*.vue" -type f 2>/dev/null | grep -v "^${FILE}$" | head -10)
COUNT=$(echo "$MATCHES" | grep -c . 2>/dev/null || echo 0)

[[ "$COUNT" -lt 1 ]] && exit 0

MSG=$(cat <<EOF
POST-WRITE AUDIT — you just touched $BASENAME (suffix detected: $SUFFIX).

Existing files with the same suffix in assets/app/:
$MATCHES

Re-confirm:
1. Is one of these implementing the SAME concept you just wrote? If yes, you should have reused or refactored to extract a shared component.
2. If your file is genuinely a new variant, say so explicitly in the next message and continue. Otherwise, STOP and reread at least one of the matches.

This audit fires automatically on any .vue/.ts file with a structural suffix. It is silent if no near-twins exist.
EOF
)

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'
exit 0
