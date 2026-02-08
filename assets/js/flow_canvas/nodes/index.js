/**
 * Node type registry — aggregates per-type modules.
 *
 * Usage:
 *   import { getNodeDef, NODE_CONFIGS } from "./nodes/index.js";
 *   const def = getNodeDef("dialogue");
 *   def.getPreviewText(data);
 */

import entry from "./entry.js";
import exit from "./exit.js";
import dialogue from "./dialogue.js";
import hub from "./hub.js";
import condition from "./condition.js";
import instruction from "./instruction.js";
import jump from "./jump.js";
import subflow from "./subflow.js";
import scene from "./scene.js";

const NODE_DEFS = { entry, exit, dialogue, hub, condition, instruction, jump, subflow, scene };

/**
 * Returns the full definition object for a node type.
 * @param {string} type
 * @returns {object|undefined}
 */
export function getNodeDef(type) {
  return NODE_DEFS[type];
}

/**
 * Aggregated configs map (used by FlowNode and StoryarnNode).
 * Same shape as the old NODE_CONFIGS.
 */
export const NODE_CONFIGS = Object.fromEntries(
  Object.entries(NODE_DEFS).map(([type, def]) => [type, def.config]),
);
