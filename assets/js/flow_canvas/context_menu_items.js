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
  LayoutGrid,
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
  layoutGrid: createIconHTML(LayoutGrid, { size: ICON_SIZE }),
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

/** Node types the user can add (all except entry). Keys match server label keys. */
const ADDABLE_TYPES = [
  { type: "dialogue", labelKey: "dialogue", icon: ICONS.dialogue },
  { type: "condition", labelKey: "condition", icon: ICONS.condition },
  { type: "instruction", labelKey: "instruction", icon: ICONS.instruction },
  { type: "hub", labelKey: "hub", icon: ICONS.hub },
  { type: "jump", labelKey: "jump", icon: ICONS.jump },
  { type: "exit", labelKey: "exit", icon: ICONS.exit },
  { type: "subflow", labelKey: "subflow", icon: ICONS.subflow },
  { type: "scene", labelKey: "scene", icon: ICONS.scene },
];

/**
 * Builds per-type context menu items.
 * @param {Object} hook - The FlowCanvas hook instance (for pushEvent)
 * @returns {Function} items(context, plugin) → { searchBar, list }
 */
export function createContextMenuItems(hook) {
  /** Look up a translated label, falling back to the key itself. */
  const t = (key) => hook.labels?.[key] || key;

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
            label: t("add_node"),
            key: "add_node",
            icon: ICONS.plus,
            subitems: ADDABLE_TYPES.map(({ type, labelKey, icon }) => ({
              label: t(labelKey),
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
            label: t("play_preview"),
            key: "play_preview",
            icon: ICONS.play,
            handler: () => {
              const path = window.location.pathname.replace(/\/$/, "");
              window.location.href = `${path}/play`;
            },
          },
          {
            label: t("start_debugging"),
            key: "start_debug",
            icon: ICONS.bug,
            handler: () => hook.pushEvent("debug_start", {}),
          },
          {
            label: t("auto_layout"),
            key: "auto_layout",
            icon: ICONS.layoutGrid,
            handler: () => hook.performAutoLayout(),
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
          label: t("view_referencing_flows"),
          key: "view_refs",
          icon: ICONS.externalLink,
          handler: () => hook.pushEvent("navigate_to_node", { id: String(nodeDbId) }),
        });
        // Entry nodes cannot be deleted or duplicated
        return { searchBar: false, list };

      case "dialogue":
        list.push({
          label: t("open_editor_panel"),
          key: "edit",
          icon: ICONS.pencil,
          handler: () => hook.pushEvent("open_screenplay", { id: String(nodeDbId) }),
        });
        list.push({
          label: t("preview_from_here"),
          key: "preview",
          icon: ICONS.play,
          handler: () => hook.pushEvent("start_preview", { id: nodeDbId }),
        });
        list.push({
          label: t("generate_technical_id"),
          key: "generate_id",
          icon: ICONS.hash,
          handler: () => hook.pushEvent("generate_technical_id", {}),
        });
        break;

      case "condition":
        list.push({
          label: t("toggle_switch_mode"),
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
          label: t("locate_referencing_jumps"),
          key: "locate_jumps",
          icon: ICONS.search,
          handler: () => hook.pushEvent("navigate_to_jumps", { id: String(nodeDbId) }),
        });
        break;

      case "jump":
        list.push({
          label: t("locate_target_hub"),
          key: "locate_hub",
          icon: ICONS.search,
          handler: () => hook.pushEvent("navigate_to_hub", { id: String(nodeDbId) }),
        });
        break;

      case "exit": {
        const hasRef = nodeData.referenced_flow_id;
        if (hasRef) {
          list.push({
            label: t("open_referenced_flow"),
            key: "open_flow",
            icon: ICONS.externalLink,
            handler: () =>
              hook.pushEvent("navigate_to_exit_flow", {
                "flow-id": String(nodeData.referenced_flow_id),
              }),
          });
        } else if (nodeData.exit_mode === "flow_reference") {
          list.push({
            label: t("create_linked_flow"),
            key: "create_flow",
            icon: ICONS.link,
            handler: () => hook.pushEvent("create_linked_flow", { "node-id": String(nodeDbId) }),
          });
        }
        break;
      }

      case "subflow": {
        const refId = nodeData.referenced_flow_id;
        if (refId) {
          list.push({
            label: t("open_referenced_flow"),
            key: "open_flow",
            icon: ICONS.externalLink,
            handler: () => hook.pushEvent("navigate_to_subflow", { "flow-id": String(refId) }),
          });
        } else {
          list.push({
            label: t("create_linked_flow"),
            key: "create_flow",
            icon: ICONS.link,
            handler: () => hook.pushEvent("create_linked_flow", { "node-id": String(nodeDbId) }),
          });
        }
        break;
      }

      case "scene":
        list.push({
          label: t("generate_technical_id"),
          key: "generate_id",
          icon: ICONS.hash,
          handler: () => hook.pushEvent("generate_technical_id", {}),
        });
        break;
    }

    // Common items (all types except entry, which returned early)
    list.push({
      label: t("duplicate"),
      key: "duplicate",
      icon: ICONS.copy,
      handler: () => hook.pushEvent("duplicate_node", { id: nodeDbId }),
    });
    list.push({
      label: t("delete"),
      key: "delete",
      icon: ICONS.trash,
      handler: () => hook.pushEvent("delete_node", { id: nodeDbId }),
    });

    return { searchBar: false, list };
  };
}
