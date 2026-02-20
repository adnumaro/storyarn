/**
 * Custom items function for the rete-context-menu-plugin.
 *
 * Receives `context` ('root' | node | connection) and returns
 * { searchBar, list } per the plugin's API.
 *
 * @see https://retejs.org/docs/guides/context-menu
 */

import {
  Box,
  Bug,
  Clapperboard,
  Copy,
  ExternalLink,
  GitBranch,
  Hash,
  Link,
  LogIn,
  LogOut,
  MessageSquare,
  Pencil,
  Play,
  Plus,
  Search,
  Square,
  ToggleLeft,
  Trash2,
  Zap,
} from "lucide";
import { createIconHTML } from "./node_config.js";

const ICON_SIZE = 14;

/** Pre-create icon HTML strings at module level. */
const ICONS = {
  // Root menu
  plus: createIconHTML(Plus, { size: ICON_SIZE }),
  play: createIconHTML(Play, { size: ICON_SIZE }),
  bug: createIconHTML(Bug, { size: ICON_SIZE }),
  // Node types
  dialogue: createIconHTML(MessageSquare, { size: ICON_SIZE }),
  condition: createIconHTML(GitBranch, { size: ICON_SIZE }),
  instruction: createIconHTML(Zap, { size: ICON_SIZE }),
  hub: createIconHTML(LogIn, { size: ICON_SIZE }),
  jump: createIconHTML(LogOut, { size: ICON_SIZE }),
  exit: createIconHTML(Square, { size: ICON_SIZE }),
  subflow: createIconHTML(Box, { size: ICON_SIZE }),
  scene: createIconHTML(Clapperboard, { size: ICON_SIZE }),
  // Node actions
  pencil: createIconHTML(Pencil, { size: ICON_SIZE }),
  search: createIconHTML(Search, { size: ICON_SIZE }),
  hash: createIconHTML(Hash, { size: ICON_SIZE }),
  toggleLeft: createIconHTML(ToggleLeft, { size: ICON_SIZE }),
  externalLink: createIconHTML(ExternalLink, { size: ICON_SIZE }),
  link: createIconHTML(Link, { size: ICON_SIZE }),
  copy: createIconHTML(Copy, { size: ICON_SIZE }),
  trash: createIconHTML(Trash2, { size: ICON_SIZE }),
};

/** Node types the user can add (all except entry). */
const ADDABLE_TYPES = [
  { type: "dialogue", label: "Dialogue", icon: ICONS.dialogue },
  { type: "condition", label: "Condition", icon: ICONS.condition },
  { type: "instruction", label: "Instruction", icon: ICONS.instruction },
  { type: "hub", label: "Hub", icon: ICONS.hub },
  { type: "jump", label: "Jump", icon: ICONS.jump },
  { type: "exit", label: "Exit", icon: ICONS.exit },
  { type: "subflow", label: "Subflow", icon: ICONS.subflow },
  { type: "scene", label: "Scene", icon: ICONS.scene },
];

/**
 * Builds per-type context menu items.
 * @param {Object} hook - The FlowCanvas hook instance (for pushEvent)
 * @returns {Function} items(context, plugin) → { searchBar, list }
 */
export function createContextMenuItems(hook) {
  return function items(context, _plugin) {
    // Connection right-click — no items
    if (context !== "root" && "source" in context && "target" in context) {
      return { searchBar: false, list: [] };
    }

    // Background right-click — canvas actions
    if (context === "root") {
      const pos = hook.area?.area?.pointer;

      return {
        searchBar: false,
        list: [
          {
            label: "Add node",
            key: "add_node",
            icon: ICONS.plus,
            subitems: ADDABLE_TYPES.map(({ type, label, icon }) => ({
              label,
              icon,
              key: `add_${type}`,
              handler: () =>
                hook.pushEvent("add_node", {
                  type,
                  position_x: pos?.x ?? 200,
                  position_y: pos?.y ?? 200,
                }),
            })),
          },
          {
            label: "Start debugging",
            key: "start_debug",
            icon: ICONS.bug,
            handler: () => hook.pushEvent("debug_start", {}),
          },
        ],
      };
    }

    // Node right-click — per-type items
    const nodeDbId = context.nodeId;
    const nodeType = context.nodeType;
    const nodeData = context.nodeData || {};
    const list = [];

    // Select node if not already selected
    if (hook.selectedNodeId !== nodeDbId) {
      hook.selectedNodeId = nodeDbId;
      hook.pushEvent("node_selected", { id: nodeDbId });
      hook.floatingToolbar?.show(nodeDbId);
    }

    switch (nodeType) {
      case "entry":
        list.push({
          label: "View referencing flows",
          key: "view_refs",
          icon: ICONS.externalLink,
          handler: () => hook.pushEvent("navigate_to_node", { id: String(nodeDbId) }),
        });
        // Entry nodes cannot be deleted or duplicated
        return { searchBar: false, list };

      case "dialogue":
        list.push({
          label: "Edit",
          key: "edit",
          icon: ICONS.pencil,
          handler: () => hook.pushEvent("open_screenplay", {}),
        });
        list.push({
          label: "Preview from here",
          key: "preview",
          icon: ICONS.play,
          handler: () => hook.pushEvent("start_preview", { id: nodeDbId }),
        });
        list.push({
          label: "Generate technical ID",
          key: "generate_id",
          icon: ICONS.hash,
          handler: () => hook.pushEvent("generate_technical_id", {}),
        });
        break;

      case "condition":
        list.push({
          label: "Toggle switch mode",
          key: "toggle_switch",
          icon: ICONS.toggleLeft,
          handler: () => hook.pushEvent("toggle_switch_mode", {}),
        });
        break;

      case "instruction":
        // No extra items beyond common
        break;

      case "hub":
        list.push({
          label: "Locate referencing jumps",
          key: "locate_jumps",
          icon: ICONS.search,
          handler: () => hook.pushEvent("navigate_to_jumps", { id: String(nodeDbId) }),
        });
        break;

      case "jump":
        list.push({
          label: "Locate target hub",
          key: "locate_hub",
          icon: ICONS.search,
          handler: () => hook.pushEvent("navigate_to_hub", { id: String(nodeDbId) }),
        });
        break;

      case "exit": {
        const hasRef = nodeData.referenced_flow_id;
        if (hasRef) {
          list.push({
            label: "Open referenced flow",
            key: "open_flow",
            icon: ICONS.externalLink,
            handler: () =>
              hook.pushEvent("navigate_to_exit_flow", {
                "flow-id": String(nodeData.referenced_flow_id),
              }),
          });
        } else if (nodeData.exit_mode === "flow_reference") {
          list.push({
            label: "Create linked flow",
            key: "create_flow",
            icon: ICONS.link,
            handler: () =>
              hook.pushEvent("create_linked_flow", { "node-id": String(nodeDbId) }),
          });
        }
        break;
      }

      case "subflow": {
        const refId = nodeData.referenced_flow_id;
        if (refId) {
          list.push({
            label: "Open referenced flow",
            key: "open_flow",
            icon: ICONS.externalLink,
            handler: () =>
              hook.pushEvent("navigate_to_subflow", { "flow-id": String(refId) }),
          });
        } else {
          list.push({
            label: "Create linked flow",
            key: "create_flow",
            icon: ICONS.link,
            handler: () =>
              hook.pushEvent("create_linked_flow", { "node-id": String(nodeDbId) }),
          });
        }
        break;
      }

      case "scene":
        list.push({
          label: "Generate technical ID",
          key: "generate_id",
          icon: ICONS.hash,
          handler: () => hook.pushEvent("generate_technical_id", {}),
        });
        break;
    }

    // Common items (all types except entry, which returned early)
    list.push({
      label: "Duplicate",
      key: "duplicate",
      icon: ICONS.copy,
      handler: () => hook.pushEvent("duplicate_node", { id: nodeDbId }),
    });
    list.push({
      label: "Delete",
      key: "delete",
      icon: ICONS.trash,
      handler: () => hook.pushEvent("delete_node", { id: nodeDbId }),
    });

    return { searchBar: false, list };
  };
}
