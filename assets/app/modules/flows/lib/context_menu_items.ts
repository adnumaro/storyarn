/**
 * Items function for rete-context-menu-plugin.
 *
 * Receives `'root'` (canvas right-click) or a FlowNode (node right-click) and
 * returns `{ searchBar, list }` per the plugin's API. Each item has
 * `{ label, key, handler, icon?, subitems? }`. Subitems are NOT implemented in
 * the 4c1-plus custom Menu — deferred to 4c2.
 *
 * @see docs/audit/flow-context-menu-broken-after-vue-migration.md
 */

import type { Component } from "vue";
import { Clapperboard, Copy, LayoutGrid, StickyNote, Trash2 } from "lucide-vue-next";

import { i18n } from "@app/i18n";
import type { FlowNode } from "./flow-node";
import type { HookProxy } from "../services/editorHandlers";

// Extended item shape: adds an optional Vue icon component. Base shape (label,
// key, handler, subitems) matches rete-context-menu-plugin's `Item` type.
export interface FlowContextMenuItem {
  label: string;
  key: string;
  icon?: Component;
  handler(): void;
  subitems?: FlowContextMenuItem[];
}

export interface FlowContextMenuItemsCollection {
  searchBar: boolean;
  list: FlowContextMenuItem[];
}

type ContextArg = "root" | FlowNode;

const NON_ANNOTATION_TYPES = new Set([
  "entry",
  "exit",
  "dialogue",
  "condition",
  "instruction",
  "hub",
  "jump",
  "subflow",
]);

export function createContextMenuItems(hook: HookProxy) {
  const t = i18n.global.t;

  return function items(context: ContextArg): FlowContextMenuItemsCollection {
    if (context === "root") {
      return rootMenu(hook, t);
    }
    return nodeMenu(hook, context, t);
  };
}

// -- Canvas menu ------------------------------------------------------------

function rootMenu(hook: HookProxy, t: (key: string) => string): FlowContextMenuItemsCollection {
  const pointerPos = getAreaPointer(hook);

  return {
    searchBar: false,
    list: [
      {
        key: "add_note",
        label: t("flows.context_menu.add_note"),
        icon: StickyNote,
        handler: () =>
          hook.pushEvent("add_annotation", {
            position_x: pointerPos.x,
            position_y: pointerPos.y,
          }),
      },
      {
        key: "auto_layout",
        label: t("flows.context_menu.auto_layout"),
        icon: LayoutGrid,
        handler: () => hook.pushEvent("auto_layout", {}),
      },
    ],
  };
}

// -- Node menu --------------------------------------------------------------

function nodeMenu(
  hook: HookProxy,
  node: FlowNode,
  t: (key: string) => string,
): FlowContextMenuItemsCollection {
  const nodeDbId = node.nodeId;
  const nodeType = node.nodeType;

  // Entry nodes cannot be duplicated or deleted; annotations have a different
  // subset. For 4c1-plus scope we only wire the common actions.
  const list: FlowContextMenuItem[] = [];

  // Duplicate — all except entry
  if (nodeType !== "entry") {
    list.push({
      key: "duplicate",
      label: t("flows.context_menu.duplicate"),
      icon: Copy,
      handler: () => hook.pushEvent("duplicate_node", { id: nodeDbId }),
    });
  }

  // Create sequence from here — only on nodes that are on the execution path
  if (NON_ANNOTATION_TYPES.has(nodeType)) {
    list.push({
      key: "create_sequence",
      label: t("flows.context_menu.create_sequence"),
      icon: Clapperboard,
      handler: () => hook.pushEvent("create_sequence_from_node", { node_id: nodeDbId }),
    });
  }

  // Delete — all except entry
  if (nodeType !== "entry") {
    list.push({
      key: "delete",
      label: t("flows.context_menu.delete"),
      icon: Trash2,
      handler: () => hook.pushEvent("delete_node", { id: nodeDbId }),
    });
  }

  return { searchBar: false, list };
}

// -- Helpers ----------------------------------------------------------------

// rete-area-plugin 2.x exposes the current pointer position via
// `area.area.pointer`. Falls back to a fixed offset if unavailable.
function getAreaPointer(hook: HookProxy): { x: number; y: number } {
  const area = hook.area as unknown as {
    area?: { pointer?: { x: number; y: number } };
  };
  return area?.area?.pointer ?? { x: 200, y: 200 };
}
