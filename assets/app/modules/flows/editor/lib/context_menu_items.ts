/**
 * Items function for rete-context-menu-plugin.
 *
 * Receives `'root'` (canvas right-click) or a FlowNode (node right-click) and
 * returns `{ searchBar, list }` per the plugin's API. Each item has
 * `{ label, key, handler, icon?, subitems? }`. Subitems are NOT implemented in
 * the 4c1-plus custom Menu — deferred to 4c2.
 *
 * @see docs/audit/flow-context-menu-broken-after-vue-migration.md
 *
 * Semantic rules:
 *
 * - When there is a non-empty selection, the menu ALWAYS operates on that
 *   selection — regardless of whether the right-click happened on canvas,
 *   on a selected node, or on an unselected node. The click target is
 *   ignored in favour of the selection.
 * - When there is no selection, fall back to the traditional behaviour:
 *   canvas right-click → canvas menu, node right-click → per-node menu.
 * - Every menu always ends with the canvas-level fallbacks (add_note,
 *   auto_layout) so the user never sees a literally empty menu.
 */

import type { Component } from "vue";
import { Clapperboard, Copy, LayoutGrid, StickyNote, Trash2 } from "lucide-vue-next";

import { i18n } from "@/app/i18n";
import { FlowNode } from "./flow-node";
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
type Translator = (key: string) => string;

export function createContextMenuItems(hook: HookProxy) {
  const t = i18n.global.t;

  return function items(context: ContextArg): FlowContextMenuItemsCollection {
    const selectedIds = getSelectedNodeDbIds(hook);

    if (selectedIds.length >= 1) {
      return selectionMenu(hook, selectedIds, t);
    }

    if (context === "root") {
      return rootMenu(hook, t);
    }
    return nodeMenu(hook, context, t);
  };
}

// -- Selection menu ----------------------------------------------------------

function selectionMenu(
  hook: HookProxy,
  selectedIds: Array<string | number>,
  t: Translator,
): FlowContextMenuItemsCollection {
  const list: FlowContextMenuItem[] = [];

  const nodes = selectedIds
    .map((id) => hook.editor.getNode(`node-${id}`))
    .filter((n): n is FlowNode => n instanceof FlowNode);

  const hasEntry = nodes.some((n) => n.nodeType === "entry");
  const allAnnotations = nodes.length > 0 && nodes.every((n) => n.nodeType === "annotation");

  // Create sequence — valid if the selection shares a parent and isn't
  // purely annotations. Hidden when mixed parents would produce a
  // `:mixed_parents` server rejection.
  if (!allAnnotations && sameParentForNodeIds(hook, selectedIds)) {
    list.push({
      key: "create_sequence",
      label: t("flows.context_menu.create_sequence_from_selection"),
      icon: Clapperboard,
      handler: () => hook.pushEvent("wrap_selection_in_sequence", { node_ids: selectedIds }),
    });
  }

  // Duplicate — available when the selection doesn't include Entry (singleton,
  // can't be duplicated per flow).
  if (!hasEntry) {
    list.push({
      key: "duplicate",
      label: t("flows.context_menu.duplicate"),
      icon: Copy,
      handler: () => {
        for (const id of selectedIds) {
          hook.pushEvent("duplicate_node", { id });
        }
      },
    });
  }

  // Delete — available when the selection doesn't include Entry.
  if (!hasEntry) {
    list.push({
      key: "delete",
      label: t("flows.context_menu.delete"),
      icon: Trash2,
      handler: () => {
        for (const id of selectedIds) {
          hook.pushEvent("delete_node", { id });
        }
      },
    });
  }

  appendCanvasFallbacks(hook, list, t);
  return { searchBar: false, list };
}

// -- Canvas menu ------------------------------------------------------------

function rootMenu(hook: HookProxy, t: Translator): FlowContextMenuItemsCollection {
  const list: FlowContextMenuItem[] = [];
  appendCanvasFallbacks(hook, list, t);
  return { searchBar: false, list };
}

// -- Node menu --------------------------------------------------------------

function nodeMenu(hook: HookProxy, node: FlowNode, t: Translator): FlowContextMenuItemsCollection {
  const nodeDbId = node.nodeId;
  const nodeType = node.nodeType;

  const list: FlowContextMenuItem[] = [];

  if (nodeType !== "entry") {
    list.push({
      key: "duplicate",
      label: t("flows.context_menu.duplicate"),
      icon: Copy,
      handler: () => hook.pushEvent("duplicate_node", { id: nodeDbId }),
    });
  }

  if (nodeType !== "annotation") {
    list.push({
      key: "create_sequence",
      label: t("flows.context_menu.create_sequence_from_selection"),
      icon: Clapperboard,
      handler: () => hook.pushEvent("wrap_selection_in_sequence", { node_ids: [nodeDbId] }),
    });
  }

  if (nodeType !== "entry") {
    list.push({
      key: "delete",
      label: t("flows.context_menu.delete"),
      icon: Trash2,
      handler: () => hook.pushEvent("delete_node", { id: nodeDbId }),
    });
  }

  appendCanvasFallbacks(hook, list, t);
  return { searchBar: false, list };
}

// -- Helpers ----------------------------------------------------------------

function appendCanvasFallbacks(hook: HookProxy, list: FlowContextMenuItem[], t: Translator): void {
  const pointer = getAreaPointer(hook);
  list.push({
    key: "add_note",
    label: t("flows.context_menu.add_note"),
    icon: StickyNote,
    handler: () =>
      hook.pushEvent("add_annotation", {
        position_x: pointer.x,
        position_y: pointer.y,
      }),
  });
  list.push({
    key: "auto_layout",
    label: t("flows.context_menu.auto_layout"),
    icon: LayoutGrid,
    handler: () => {
      void hook.performAutoLayout();
    },
  });
}

// rete-area-plugin 2.x exposes the current pointer position via
// `area.area.pointer`. Falls back to a fixed offset if unavailable.
function getAreaPointer(hook: HookProxy): { x: number; y: number } {
  const area = hook.area as unknown as {
    area?: { pointer?: { x: number; y: number } };
  };
  return area?.area?.pointer ?? { x: 200, y: 200 };
}

/**
 * Reads the DB ids of all currently-selected FlowNodes from the reactive
 * `flowContext.selectedReteIds` set — single source of truth for selection
 * state, kept in sync by the selector monkey-patch in
 * `setup.ts::finalizeSetup`.
 *
 * Sequence-type nodes are included (they're flow_nodes too post-Phase 1).
 */
function getSelectedNodeDbIds(hook: HookProxy): Array<string | number> {
  const set = hook._flowContext?.selectedReteIds;
  if (!set || set.size === 0) return [];

  const out: Array<string | number> = [];
  for (const reteId of set) {
    const reteNode = hook.editor.getNode(String(reteId));
    if (!reteNode || !(reteNode instanceof FlowNode)) continue;
    out.push(reteNode.nodeId);
  }
  return out;
}

/** True iff every DB id in the list points to a node sharing the same
 *  rete `parent` (= same parent sequence, or all at root). Matches the
 *  server-side `SequenceCrud.wrap_selection_in_sequence/3` mixed-parents
 *  validation so the menu item only shows when the wrap would succeed. */
function sameParentForNodeIds(hook: HookProxy, nodeDbIds: Array<string | number>): boolean {
  if (nodeDbIds.length <= 1) return true;

  const parents = new Set<string | undefined>();
  for (const dbId of nodeDbIds) {
    const reteNode = hook.editor.getNode(`node-${dbId}`);
    if (!reteNode || !(reteNode instanceof FlowNode)) continue;
    parents.add(reteNode.parent);
  }
  return parents.size <= 1;
}
