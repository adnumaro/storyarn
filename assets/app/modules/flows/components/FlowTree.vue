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
import FlowTreeNode from "./FlowTreeNode.vue";
import FlowTreeRoot from "./FlowTreeRoot.vue";

export interface FlowTreeItem {
  id: number | string;
  name: string;
  is_main?: boolean;
  children?: FlowTreeItem[];
}

interface DnDDropEvent {
  draggedItems: { item: FlowTreeItem; items: FlowTreeItem[] }[];
  hoveredDraggable: { item: FlowTreeItem; items: FlowTreeItem[]; element: HTMLElement } | null;
  dropZone: { items: FlowTreeItem[] } | null;
  provider: { pointer: { value: { current: { x: number; y: number } } } } | null;
  helpers: {
    suggestSort: (
      dir: string,
    ) => { sourceItems: FlowTreeItem[]; targetItems: FlowTreeItem[]; sameList: boolean } | null;
  };
}

const {
  flowsTree = [],
  selectedFlowId = null,
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  flowsTree: FlowTreeItem[];
  selectedFlowId: string | number | null;
  canEdit: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const live = useLive();
const searchQuery = ref("");
const deleteDialogOpen = ref(false);
const pendingDeleteFlow = ref<FlowTreeItem | null>(null);

// Local reactive copy for DnD mutations
const localTree = ref<FlowTreeItem[]>([...flowsTree]);
watch(
  () => flowsTree,
  (v) => {
    localTree.value = v;
  },
  { deep: true },
);

function flowHref(flow: FlowTreeItem): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${flow.id}`;
}

function matchesSearch(node: FlowTreeItem, query: string): boolean {
  if (node.name.toLowerCase().includes(query)) return true;
  if (node.children) {
    return node.children.some((child) => matchesSearch(child, query));
  }
  return false;
}

function filterTree(nodes: FlowTreeItem[], query: string): FlowTreeItem[] {
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

function createFlow() {
  live.pushEvent("create_flow", {});
}

function createChildFlow(parentId: number | string): void {
  live.pushEvent("create_child_flow", { parent_id: parentId });
}

function setMainFlow(flowId: number | string): void {
  live.pushEvent("set_main_flow", { id: String(flowId) });
}

function requestDelete(flow: FlowTreeItem): void {
  pendingDeleteFlow.value = flow;
  deleteDialogOpen.value = true;
}

function confirmDelete() {
  if (pendingDeleteFlow.value) {
    live.pushEvent("set_pending_delete_flow", {
      id: pendingDeleteFlow.value.id,
    });
    live.pushEvent("confirm_delete_flow", {});
  }
  deleteDialogOpen.value = false;
  pendingDeleteFlow.value = null;
}

// DnD tree mutation helpers
function applyToTree(oldArr: FlowTreeItem[], newArr: FlowTreeItem[]): void {
  if (oldArr === localTree.value) {
    localTree.value = newArr;
  } else {
    findAndReplace(localTree.value, oldArr, newArr);
  }
}

function findAndReplace(
  nodes: FlowTreeItem[],
  oldArr: FlowTreeItem[],
  newArr: FlowTreeItem[],
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

function findNodeContext(
  nodes: FlowTreeItem[],
  nodeId: number | string,
  parentId: number | string | null = null,
): { parentId: number | string | null; position: number } | null {
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    if (node.id === nodeId) return { parentId, position: i };
    if (node.children) {
      const found = findNodeContext(node.children, nodeId, node.id);
      if (found) return found;
    }
  }
  return null;
}

function findNodeById(nodes: FlowTreeItem[], nodeId: number | string): FlowTreeItem | null {
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
  nodes: FlowTreeItem[],
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

function getPointerZone(e: DnDDropEvent): "before" | "after" | "nest" | null {
  const el = e.hoveredDraggable?.element;
  const pointer = e.provider?.pointer?.value?.current;
  if (!el || !pointer) return null;
  const rect = el.getBoundingClientRect();
  const relY = (pointer.y - rect.top) / rect.height;
  if (relY <= 0.3) return "before";
  if (relY >= 0.7) return "after";
  return "nest";
}

function handleNestDrop(dropEvent: DnDDropEvent, draggedNode: FlowTreeItem, hoveredNode: FlowTreeItem): void {
  if (isDescendantOf(localTree.value, draggedNode.id, hoveredNode.id)) return;

  const targetNode = findNodeById(localTree.value, hoveredNode.id);
  if (!targetNode) return;

  const srcArr = dropEvent.draggedItems[0]?.items;
  if (srcArr) {
    applyToTree(srcArr, srcArr.filter((n) => n.id !== draggedNode.id));
  }

  if (!targetNode.children) targetNode.children = [];
  targetNode.children.push(draggedNode);

  pushMove(draggedNode.id, hoveredNode.id, targetNode.children.length - 1);
}

function handleSiblingSort(dropEvent: DnDDropEvent, draggedNode: FlowTreeItem): void {
  const r = dropEvent.helpers.suggestSort("vertical");
  if (!r) return;

  const srcArr = dropEvent.draggedItems[0]?.items;
  const tgtArr = dropEvent.hoveredDraggable?.items ?? dropEvent.dropZone?.items;
  if (!srcArr || !tgtArr) return;

  applyToTree(srcArr, r.sourceItems);
  if (!r.sameList) {
    applyToTree(tgtArr, r.targetItems);
  }

  const ctx = findNodeContext(localTree.value, draggedNode.id);
  if (ctx) {
    pushMove(draggedNode.id, ctx.parentId, ctx.position);
  }
}

function handleDrop(e: unknown): void {
  const dropEvent = e as DnDDropEvent;
  const draggedNode = dropEvent.draggedItems[0]?.item;
  const hoveredNode = dropEvent.hoveredDraggable?.item;
  const zone = getPointerZone(dropEvent);

  if (!draggedNode) return;

  if (zone === "nest" && hoveredNode && hoveredNode.id !== draggedNode.id) {
    handleNestDrop(dropEvent, draggedNode, hoveredNode);
    return;
  }

  handleSiblingSort(dropEvent, draggedNode);
}
</script>

<template>
  <div class="space-y-2">
    <!-- Search -->
    <div class="px-1">
      <Input
        v-model="searchQuery"
        type="search"
        placeholder="Filter flows..."
        class="h-7 text-xs"
      />
    </div>

    <!-- Empty state -->
    <div
      v-if="filteredTree.length === 0"
      class="px-2 py-4 text-xs text-muted-foreground text-center"
    >
      No flows yet
    </div>

    <!-- Tree -->
    <DnDProvider v-if="filteredTree.length > 0">
      <FlowTreeRoot :items="filteredTree" @drop="handleDrop">
        <FlowTreeNode
          v-for="(node, index) in filteredTree"
          :key="node.id"
          :node="node"
          :index="index"
          :siblings="filteredTree"
          :selected-flow-id="selectedFlowId"
          :can-edit="canEdit"
          :depth="0"
          :search-active="!!searchQuery"
          :flow-href="flowHref"
          @create-child="createChildFlow"
          @request-delete="requestDelete"
          @set-main="setMainFlow"
          @drop="handleDrop"
        />
      </FlowTreeRoot>
    </DnDProvider>

    <!-- New Flow button -->
    <div v-if="canEdit" class="pt-2 px-1">
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground"
        @click="createFlow"
      >
        <Plus class="size-3.5" />
        New Flow
      </Button>
    </div>

    <!-- Delete confirmation dialog -->
    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete flow?</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete "{{ pendingDeleteFlow?.name }}"?
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
