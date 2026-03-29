<script setup>
import { DnDProvider } from "@vue-dnd-kit/core";
import { Plus } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Button } from "@/vue/components/ui/button/index.js";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/vue/components/ui/dialog/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import FlowTreeNode from "./FlowTreeNode.vue";
import FlowTreeRoot from "./FlowTreeRoot.vue";

const props = defineProps({
	flowsTree: { type: Array, default: () => [] },
	selectedFlowId: { type: [String, Number], default: null },
	canEdit: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
});

const live = useLive();
const searchQuery = ref("");
const deleteDialogOpen = ref(false);
const pendingDeleteFlow = ref(null);

// Local reactive copy for DnD mutations
const localTree = ref([...props.flowsTree]);
watch(
	() => props.flowsTree,
	(v) => {
		localTree.value = v;
	},
	{ deep: true },
);

function flowHref(flow) {
	return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows/${flow.id}`;
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

function createFlow() {
	live.pushEvent("create_flow", {});
}

function createChildFlow(parentId) {
	live.pushEvent("create_child_flow", { parent_id: parentId });
}

function setMainFlow(flowId) {
	live.pushEvent("set_main_flow", { id: String(flowId) });
}

function requestDelete(flow) {
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
		if (node.children && findAndReplace(node.children, oldArr, newArr))
			return true;
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

	// Center zone: nest as last child
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

	// Top/bottom: sibling sort
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
        placeholder="Filter flows..."
        class="h-7 text-xs"
      />
    </div>

    <!-- Empty state -->
    <div v-if="filteredTree.length === 0" class="px-2 py-4 text-xs text-muted-foreground text-center">
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
