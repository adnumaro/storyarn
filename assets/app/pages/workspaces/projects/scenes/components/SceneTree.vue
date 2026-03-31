<script setup>
import { DnDProvider } from "@vue-dnd-kit/core";
import { Plus } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { useLive } from "@composables/useLive";
import SceneTreeNode from "./SceneTreeNode.vue";
import SceneTreeRoot from "./SceneTreeRoot.vue";

const props = defineProps({
  scenesTree: { type: Array, default: () => [] },
  selectedSceneId: { type: [String, Number], default: null },
  canEdit: { type: Boolean, default: false },
  workspaceSlug: { type: String, required: true },
  projectSlug: { type: String, required: true },
});

const live = useLive();
const searchQuery = ref("");
const deleteDialogOpen = ref(false);
const pendingDeleteScene = ref(null);

// Local reactive copy for DnD mutations
const localTree = ref([...props.scenesTree]);
watch(
  () => props.scenesTree,
  (v) => {
    localTree.value = v;
  },
  { deep: true },
);

function sceneHref(scene) {
  return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/scenes/${scene.id}`;
}

function matchesSearch(node, query) {
  if (node.name.toLowerCase().includes(query)) return true;
  if (node.children) {
    return node.children.some((child) => matchesSearch(child, query));
  }
  return false;
}

function filterTree(nodes, query) {
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

function createScene() {
  live.pushEvent("create_scene", {});
}

function createChildScene(parentId) {
  live.pushEvent("create_child_scene", { parent_id: parentId });
}

function requestDelete(scene) {
  pendingDeleteScene.value = scene;
  deleteDialogOpen.value = true;
}

function confirmDelete() {
  if (pendingDeleteScene.value) {
    live.pushEvent("set_pending_delete_scene", {
      id: pendingDeleteScene.value.id,
    });
    live.pushEvent("confirm_delete_scene", {});
  }
  deleteDialogOpen.value = false;
  pendingDeleteScene.value = null;
}

// ── Tree mutation (following vue-dnd-kit tree example) ──

function applyToTree(oldArr, newArr) {
  if (oldArr === localTree.value) {
    localTree.value = newArr;
  } else {
    findAndReplace(localTree.value, oldArr, newArr);
  }
}

function findAndReplace(nodes, oldArr, newArr) {
  for (const node of nodes) {
    if (node.children === oldArr) {
      node.children = newArr;
      return true;
    }
    if (node.children && findAndReplace(node.children, oldArr, newArr)) return true;
  }
  return false;
}

function findNodeContext(nodes, nodeId, parentId = null) {
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].id === nodeId) return { parentId, position: i };
    if (nodes[i].children) {
      const found = findNodeContext(nodes[i].children, nodeId, nodes[i].id);
      if (found) return found;
    }
  }
  return null;
}

function findNodeById(nodes, nodeId) {
  for (const n of nodes) {
    if (n.id === nodeId) return n;
    if (n.children) {
      const found = findNodeById(n.children, nodeId);
      if (found) return found;
    }
  }
  return null;
}

function isDescendantOf(nodes, ancestorId, targetId) {
  const ancestor = findNodeById(nodes, ancestorId);
  if (!ancestor?.children) return false;
  for (const c of ancestor.children) {
    if (c.id === targetId) return true;
    if (isDescendantOf(nodes, c.id, targetId)) return true;
  }
  return false;
}

function pushMove(nodeId, parentId, position) {
  live.pushEvent("move_to_parent", {
    item_id: String(nodeId),
    new_parent_id: parentId != null ? String(parentId) : "",
    position: String(position),
  });
}

function getPointerZone(e) {
  const el = e.hoveredDraggable?.element;
  const pointer = e.provider?.pointer?.value?.current;
  if (!el || !pointer) return null;
  const rect = el.getBoundingClientRect();
  const relY = (pointer.y - rect.top) / rect.height;
  if (relY <= 0.3) return "before";
  if (relY >= 0.7) return "after";
  return "nest";
}

function handleDrop(e) {
  const draggedNode = e.draggedItems[0]?.item;
  const hoveredNode = e.hoveredDraggable?.item;
  const zone = getPointerZone(e);

  if (!draggedNode) return;

  // Center zone → nest as last child
  if (zone === "nest" && hoveredNode && hoveredNode.id !== draggedNode.id) {
    if (isDescendantOf(localTree.value, draggedNode.id, hoveredNode.id)) return;

    const targetNode = findNodeById(localTree.value, hoveredNode.id);
    if (!targetNode) return;

    const srcArr = e.draggedItems[0]?.items;
    if (srcArr) {
      const filtered = srcArr.filter((n) => n.id !== draggedNode.id);
      applyToTree(srcArr, filtered);
    }

    if (!targetNode.children) targetNode.children = [];
    targetNode.children.push(draggedNode);

    pushMove(draggedNode.id, hoveredNode.id, targetNode.children.length - 1);
    return;
  }

  // Top/bottom → sibling sort
  const r = e.helpers.suggestSort("vertical");
  if (!r) return;

  const srcArr = e.draggedItems[0]?.items;
  const tgtArr = e.hoveredDraggable?.items ?? e.dropZone?.items;
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
</script>

<template>
  <div class="space-y-2">
    <!-- Search -->
    <div class="px-1">
      <Input
        v-model="searchQuery"
        type="search"
        placeholder="Filter scenes..."
        class="h-7 text-xs"
      />
    </div>

    <!-- Empty state -->
    <div
      v-if="filteredTree.length === 0"
      class="px-2 py-4 text-xs text-muted-foreground text-center"
    >
      No scenes yet
    </div>

    <!-- Tree -->
    <DnDProvider v-if="filteredTree.length > 0">
      <SceneTreeRoot :items="filteredTree" @drop="handleDrop">
        <SceneTreeNode
          v-for="(node, index) in filteredTree"
          :key="node.id"
          :node="node"
          :index="index"
          :siblings="filteredTree"
          :selected-scene-id="selectedSceneId"
          :can-edit="canEdit"
          :depth="0"
          :search-active="!!searchQuery"
          :scene-href="sceneHref"
          @create-child="createChildScene"
          @request-delete="requestDelete"
          @drop="handleDrop"
        />
      </SceneTreeRoot>
    </DnDProvider>

    <!-- New Scene button -->
    <div v-if="canEdit" class="pt-2 px-1">
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground"
        @click="createScene"
      >
        <Plus class="size-3.5" />
        New Scene
      </Button>
    </div>

    <!-- Delete confirmation dialog -->
    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete scene?</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete "{{ pendingDeleteScene?.name }}"?
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
