/**
 * Instruction node type definition.
 *
 * Includes instruction-formatting functions (absorbed from node_formatters.js).
 */
import { html } from "lit";
import { Zap } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderPreview, renderSockets } from "./render_helpers.js";

// --- Instruction formatting (was node_formatters.js) ---

/**
 * Formats a single assignment for canvas preview (sentence-style).
 * Keep in sync with lib/storyarn/flows/instruction.ex:format_assignment_short/1
 */
function formatAssignment(assignment) {
  if (!assignment.page || !assignment.variable) return null;
  const ref = `${assignment.page}.${assignment.variable}`;
  const op = assignment.operator || "set";

  if (op === "set_true") return `Set ${ref} to true`;
  if (op === "set_false") return `Set ${ref} to false`;
  if (op === "toggle") return `Toggle ${ref}`;
  if (op === "clear") return `Clear ${ref}`;

  let valueDisplay;
  if (
    assignment.value_type === "variable_ref" &&
    assignment.value_page &&
    assignment.value
  ) {
    valueDisplay = `${assignment.value_page}.${assignment.value}`;
  } else {
    valueDisplay = assignment.value || "?";
  }

  if (op === "set") return `Set ${ref} to ${valueDisplay}`;
  if (op === "add") return `Add ${valueDisplay} to ${ref}`;
  if (op === "subtract") return `Subtract ${valueDisplay} from ${ref}`;

  return `Set ${ref} to ${valueDisplay}`;
}

function getInstructionSummary(nodeData) {
  const assignments = nodeData.assignments || [];
  if (assignments.length === 0) return "";
  return assignments
    .slice(0, 3)
    .map((a) => formatAssignment(a))
    .filter(Boolean)
    .join("\n");
}

// --- Node definition ---

export default {
  config: {
    label: "Instruction",
    color: "#10b981",
    icon: createIconSvg(Zap),
    inputs: ["input"],
    outputs: ["output"],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const preview = this.getPreviewText(nodeData);
    return nodeShell(config.color, selected, html`
      ${defaultHeader(config, config.color, [])}
      ${renderPreview(preview)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
  },

  getPreviewText(data) {
    return getInstructionSummary(data);
  },

  needsRebuild(_oldData, _newData) {
    return false;
  },
};
