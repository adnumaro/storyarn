<script setup lang="ts">
import { DnDProvider } from "@vue-dnd-kit/core";
import { Plus } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button/index.ts";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { useLive } from "@composables/useLive";
import type { SheetTreeNodeData } from "../../types";
import SheetTreeNode from "./SheetTreeNode.vue";
import SheetTreeRoot from "./SheetTreeRoot.vue";

const {
  sheetsTree = [],
  selectedSheetId = null,
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  sheetsTree?: SheetTreeNodeData[];
  selectedSheetId?: string | number | null;
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const live = useLive();
const searchQuery = ref("");
const deleteDialogOpen = ref(false);
const pendingDeleteSheet = ref<SheetTreeNodeData | null>(null);

// Use a local reactive copy so suggestSort can mutate it
const localTree = ref<SheetTreeNodeData[]>([...sheetsTree]);
watch(
  () => sheetsTree,
  (v) => {
    localTree.value = v;
  },
  { deep: true },
);

function sheetHref(sheet: SheetTreeNodeData): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${sheet.id}`;
}

function matchesSearch(node: SheetTreeNodeData, query: string): boolean {
  if (node.name.toLowerCase().includes(query)) return true;
  if (node.children) {
    return node.children.some((child) => matchesSearch(child, query));
  }
  return false;
}

function filterTree(nodes: SheetTreeNodeData[], query: string): SheetTreeNodeData[] {
  return nodes
    .filter((node) => matchesSearch(node, query))
    .map((node) => ({
      ...node,
      children: node.children ? filterTree(node.children, query) : [],
    }));
}

const filteredTree = computed(() => {
  if (!searchQuery.value) return localTree.value;
  return filterTree(localTree.value, searchQuery.value.toLowerCase());
});

function createSheet(): void {
  live.pushEvent("create_sheet", {});
}

function createChildSheet(parentId: number | string): void {
  live.pushEvent("create_child_sheet", { parent_id: parentId });
}

function requestDelete(sheet: SheetTreeNodeData): void {
  pendingDeleteSheet.value = sheet;
  deleteDialogOpen.value = true;
}

function confirmDelete(): void {
  if (pendingDeleteSheet.value) {
    live.pushEvent("set_pending_delete_sheet", {
      id: pendingDeleteSheet.value.id,
    });
    live.pushEvent("confirm_delete_sheet", {});
  }
  deleteDialogOpen.value = false;
  pendingDeleteSheet.value = null;
}

// ── Tree mutation (following vue-dnd-kit tree example) ──

function applyToTree(oldArr: SheetTreeNodeData[], newArr: SheetTreeNodeData[]): void {
  if (oldArr === localTree.value) {
    localTree.value = newArr;
  } else {
    findAndReplace(localTree.value, oldArr, newArr);
  }
}

function findAndReplace(
  nodes: SheetTreeNodeData[],
  oldArr: SheetTreeNodeData[],
  newArr: SheetTreeNodeData[],
): boolean {
  for (const node of nodes) {
    if (node.children === oldArr) {
      node.children = newArr;
      return true;
    }
    if (node.children && findAndReplace(node.children, oldArr, newArr)) return true;
  }
  return false;
}

// Find parent_id and position for a node after tree mutation
function findNodeContext(
  nodes: SheetTreeNodeData[],
  nodeId: number | string,
  parentId: number | string | null = null,
): { parentId: number | string | null; position: number } | null {
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].id === nodeId) return { parentId, position: i };
    if (nodes[i].children) {
      const found = findNodeContext(nodes[i].children!, nodeId, nodes[i].id);
      if (found) return found;
    }
  }
  return null;
}

function findNodeById(
  nodes: SheetTreeNodeData[],
  nodeId: number | string,
): SheetTreeNodeData | null {
  for (const n of nodes) {
    if (n.id === nodeId) return n;
    if (n.children) {
      const found = findNodeById(n.children, nodeId);
      if (found) return found;
    }
  }
  return null;
}

function isDescendantOf(
  nodes: SheetTreeNodeData[],
  ancestorId: number | string,
  targetId: number | string,
): boolean {
  const ancestor = findNodeById(nodes, ancestorId);
  if (!ancestor?.children) return false;
  for (const c of ancestor.children) {
    if (c.id === targetId) return true;
    if (isDescendantOf(nodes, c.id, targetId)) return true;
  }
  return false;
}

function pushMove(
  nodeId: number | string,
  parentId: number | string | null,
  position: number,
): void {
  live.pushEvent("move_to_parent", {
    item_id: String(nodeId),
    new_parent_id: parentId != null ? String(parentId) : "",
    position: String(position),
  });
}

interface DndDropEvent {
  draggedItems: { item?: SheetTreeNodeData; items?: SheetTreeNodeData[] }[];
  hoveredDraggable?: {
    item?: SheetTreeNodeData;
    element?: HTMLElement;
    items?: SheetTreeNodeData[];
    placement?: { bottom?: boolean };
  };
  dropZone?: { items?: SheetTreeNodeData[] };
  helpers: {
    suggestSort: (
      dir: string,
    ) => {
      sourceItems: SheetTreeNodeData[];
      targetItems?: SheetTreeNodeData[];
      sameList?: boolean;
    } | null;
  };
  provider?: { pointer?: { value?: { current?: { x: number; y: number } } } };
}

function getPointerZone(e: DndDropEvent): "before" | "nest" | "after" | null {
  const el = e.hoveredDraggable?.element;
  const pointer = e.provider?.pointer?.value?.current;
  if (!el || !pointer) return null;
  const rect = el.getBoundingClientRect();
  const relY = (pointer.y - rect.top) / rect.height;
  if (relY <= 0.3) return "before";
  if (relY >= 0.7) return "after";
  return "nest";
}

function handleDrop(e: DndDropEvent): void {
  const draggedNode = e.draggedItems[0]?.item;
  const hoveredNode = e.hoveredDraggable?.item;
  const zone = getPointerZone(e);

  if (!draggedNode) return;

  // Center zone → nest as last child of hovered node
  if (zone === "nest" && hoveredNode && hoveredNode.id !== draggedNode.id) {
    if (isDescendantOf(localTree.value, draggedNode.id, hoveredNode.id)) return;

    const targetNode = findNodeById(localTree.value, hoveredNode.id);
    if (!targetNode) return;

    // Remove from source
    const srcArr = e.draggedItems[0]?.items;
    if (srcArr) {
      const filtered = srcArr.filter((n) => n.id !== draggedNode.id);
      applyToTree(srcArr, filtered);
    }

    // Add as last child
    if (!targetNode.children) targetNode.children = [];
    targetNode.children.push(draggedNode);

    pushMove(draggedNode.id, hoveredNode.id, targetNode.children.length - 1);
    return;
  }

  // Top/bottom placement → sibling sort via suggestSort
  const r = e.helpers.suggestSort("vertical");
  if (!r) return;

  const srcArr = e.draggedItems[0]?.items;
  const tgtArr = e.hoveredDraggable?.items ?? e.dropZone?.items;
  if (!srcArr || !tgtArr) return;

  applyToTree(srcArr, r.sourceItems);
  if (!r.sameList) {
    applyToTree(tgtArr, r.targetItems!);
  }

  const ctx = findNodeContext(localTree.value, draggedNode.id);
  if (ctx) {
    pushMove(draggedNode.id, ctx.parentId, ctx.position);
  }
}
</script>

<template>
  <div class="space-y-2">
    <!-- Search -->
    <Input v-model="searchQuery" type="search" placeholder="Filter sheets..." class="text-xs" />

    <!-- Empty state -->
    <div
      v-if="filteredTree.length === 0"
      class="px-2 py-4 text-xs text-muted-foreground text-center"
    >
      No sheets yet
    </div>

    <!-- Tree -->
    <DnDProvider v-if="filteredTree.length > 0">
      <SheetTreeRoot :items="filteredTree" @drop="(e: unknown) => handleDrop(e as DndDropEvent)">
        <SheetTreeNode
          v-for="(node, index) in filteredTree"
          :key="node.id"
          :node="node"
          :index="index"
          :siblings="filteredTree"
          :selected-sheet-id="selectedSheetId"
          :can-edit="canEdit"
          :depth="0"
          :search-active="!!searchQuery"
          :sheet-href="sheetHref"
          @create-child="createChildSheet"
          @request-delete="requestDelete"
          @drop="(e: unknown) => handleDrop(e as DndDropEvent)"
        />
      </SheetTreeRoot>
    </DnDProvider>

    <!-- New Sheet button -->
    <div v-if="canEdit" class="pt-2 px-1">
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground"
        @click="createSheet"
      >
        <Plus class="size-3.5" />
        New Sheet
      </Button>
    </div>

    <!-- Delete confirmation dialog -->
    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent class="">
        <DialogHeader>
          <DialogTitle>Delete sheet?</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete "{{ pendingDeleteSheet?.name }}"?
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" size="sm" @click="deleteDialogOpen = false">Cancel</Button>
          <Button variant="destructive" size="sm" @click="confirmDelete">Delete</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
