/**
 * Node type configurations and icon helpers for the flow canvas.
 */

import { ArrowRight, GitBranch, GitMerge, MessageSquare, Zap, createElement } from "lucide";

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
    color: "#8b5cf6",
    icon: createIconSvg(GitMerge),
    inputs: ["input"],
    outputs: ["out1", "out2", "out3", "out4"],
  },
  condition: {
    label: "Condition",
    color: "#f59e0b",
    icon: createIconSvg(GitBranch),
    inputs: ["input"],
    outputs: ["true", "false"],
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
    color: "#ef4444",
    icon: createIconSvg(ArrowRight),
    inputs: ["input"],
    outputs: [],
  },
};
