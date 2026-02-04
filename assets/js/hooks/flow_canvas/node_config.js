/**
 * Node type configurations and icon helpers for the flow canvas.
 */

import {
  ArrowDownRight,
  GitBranch,
  GitMerge,
  MessageSquare,
  Play,
  Square,
  Zap,
  createElement,
} from "lucide";

/**
 * Creates an SVG string from a Lucide icon.
 * @param {object} icon - Lucide icon component
 * @returns {string} SVG markup string
 */
export function createIconSvg(icon) {
  const el = createElement(icon, {
    width: 16,
    height: 16,
    stroke: "currentColor",
    "stroke-width": 2,
  });
  return el.outerHTML;
}

/**
 * Configuration for each node type including styling and socket definitions.
 */
export const NODE_CONFIGS = {
  entry: {
    label: "Entry",
    color: "#22c55e", // green-500
    icon: createIconSvg(Play),
    inputs: [], // No inputs - this is the starting point
    outputs: ["output"],
  },
  exit: {
    label: "Exit",
    color: "#ef4444", // red-500
    icon: createIconSvg(Square),
    inputs: ["input"], // Only inputs - this is an ending point
    outputs: [],
  },
  dialogue: {
    label: "Dialogue",
    color: "#3b82f6",
    icon: createIconSvg(MessageSquare),
    inputs: ["input"],
    outputs: ["output"], // Default single output, overridden by responses if present
    dynamicOutputs: true, // Signal that this node type can have dynamic outputs
  },
  hub: {
    label: "Hub",
    color: "#8b5cf6", // Default purple, can be customized via node data
    icon: createIconSvg(GitMerge),
    inputs: ["input"], // Multiple connections can target this single input (convergence)
    outputs: ["output"], // Single output after convergence
  },
  condition: {
    label: "Condition",
    color: "#f59e0b",
    icon: createIconSvg(GitBranch),
    inputs: ["input"],
    outputs: ["true", "false"], // Default fallback, overridden by cases if present
    dynamicOutputs: true, // Signal that this node type can have dynamic outputs from cases
  },
  instruction: {
    label: "Instruction",
    color: "#10b981",
    icon: createIconSvg(Zap),
    inputs: ["input"],
    outputs: ["output"],
  },
  jump: {
    label: "Jump",
    color: "#a855f7", // purple-500, same family as Hub
    icon: createIconSvg(ArrowDownRight),
    inputs: ["input"],
    outputs: [], // No outputs - execution teleports to target Hub
  },
};
