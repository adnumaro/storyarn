#!/usr/bin/env bash
# PreToolUse hook: when Claude is about to Write/Edit a file under
# assets/app/ or lib/storyarn{,_web}/, dump the catalog of existing
# components / modules into the model's context as a reminder.
#
# Goal: stop Claude from hand-rolling toolbars / sidebars / pickers /
# CRUD helpers that already exist. Advisory — injects context, does
# not block.
#
# Output protocol: JSON on stdout with hookSpecificOutput.additionalContext
# so the message lands in the model's context for the next turn.
#
# Triggered by: 5 consecutive offenses in one session 2026-04-25 where
# Claude shipped custom CSS / inline pickers / auto-open sidebars despite
# the codebase having shared primitives. Hook installed as a circuit
# breaker.

set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

[[ -z "$FILE" ]] && exit 0

frontend_msg() {
  local primitives shared
  primitives=$(ls "$ROOT/assets/app/components/ui/" 2>/dev/null | tr '\n' ' ')
  shared=$(ls "$ROOT/assets/app/components/"*.vue 2>/dev/null | xargs -n1 basename | tr '\n' ' ')

  cat <<EOF
Frontend write detected ($FILE).

Shadcn primitives at assets/app/components/ui/:
$primitives

Shared Vue components at assets/app/components/:
$shared

Before writing custom CSS, layout, or HTML primitives:
- Shadcn primitive covers it? (Button, Slider, Input, Popover, Command, Sheet, Tabs, Tooltip, ...)
- Shared component implements this? (AssetUploadButton, ConfirmDialog, ColorPicker, EditableText, VariableCombobox, ...)
- Toolbars: 9 implementations live at assets/app/modules/flows/components/toolbar-sections/ dispatched by FlowNodeToolbar.vue. Add to the registry; do NOT fork the wrapper.
- Sidebars: open FlowBuilderPanel.vue or FlowScreenplayEditor.vue first; both use Sidebar from assets/app/components/layout/.
- Asset pickers: AudioTab.vue inline pattern is the closest precedent today (Popover + Command + Upload). If you need it twice, EXTRACT a shared component first; do not duplicate.
- File upload: AssetUploadButton.vue + useUpload composable exist. Don't re-implement FileReader logic.

Proceed only if you can name which existing primitives you'll reuse. If you're writing scoped <style> for layout (positioning, sizing, container shape), STOP — that's almost certainly a sign you're forking something that already exists.
EOF
}

backend_msg() {
  local flows handlers
  flows=$(ls "$ROOT/lib/storyarn/flows/" 2>/dev/null | tr '\n' ' ')
  handlers=$(ls "$ROOT/lib/storyarn_web/live/flow_live/handlers/" 2>/dev/null | tr '\n' ' ')

  cat <<EOF
Backend Elixir write detected ($FILE).

flows submodules at lib/storyarn/flows/:
$flows

flow_live handlers at lib/storyarn_web/live/flow_live/handlers/:
$handlers

Before adding a function or handler:
- New CRUD function? Pick an existing CRUD module (NodeCrud, NodeUpdate, NodeDelete, NodeCreate, FlowCrud, SequenceCrud) before creating a new one.
- LiveViews must call Storyarn.Flows facade — never submodules directly. Add a defdelegate if the function is missing.
- Event handler? See lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex for the dispatch pattern. Match existing handler names (handle_node_*, handle_open_*, handle_close_*).
- Schema fields with cross-entity refs need DB-level CHECK / triggers ("blindamos, nunca confiamos"). See trg_flow_nodes_validate_parent_is_sequence as the precedent.

Proceed only if you've checked the module placement and the facade exposes what callers need.
EOF
}

MSG=""
if [[ "$FILE" =~ ^${ROOT}/assets/app/.*\.(vue|ts)$ ]]; then
  MSG=$(frontend_msg)
elif [[ "$FILE" =~ ^${ROOT}/lib/storyarn(_web)?/.*\.exs?$ ]]; then
  MSG=$(backend_msg)
else
  exit 0
fi

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $msg
  }
}'
exit 0
