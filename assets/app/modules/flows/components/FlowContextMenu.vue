<script setup>
import {
  ArrowRightToLine,
  Box,
  Clapperboard,
  Copy,
  GitBranch,
  Hash,
  LayoutGrid,
  LogIn,
  LogOut,
  MessageSquare,
  Pencil,
  Play,
  Plus,
  StickyNote,
  Trash2,
  Zap,
} from "lucide-vue-next";
import { computed, nextTick, onMounted, onUnmounted, ref } from "vue";
import { useLive } from "@composables/useLive.js";

const { containerEl, canEdit, selectedNodeId, selectedNodeType } = defineProps({
  containerEl: { type: Object, default: null },
  canEdit: { type: Boolean, default: false },
  selectedNodeId: { type: [Number, String], default: null },
  selectedNodeType: { type: String, default: null },
});

const live = useLive();
const visible = ref(false);
const x = ref(0);
const y = ref(0);
const submenu = ref(null);

const NODE_TYPES = [
  { type: "dialogue", icon: MessageSquare, label: "Dialogue" },
  { type: "condition", icon: GitBranch, label: "Condition" },
  { type: "instruction", icon: Zap, label: "Instruction" },
  { type: "hub", icon: LogIn, label: "Hub" },
  { type: "jump", icon: LogOut, label: "Jump" },
  { type: "exit", icon: ArrowRightToLine, label: "Exit" },
  { type: "subflow", icon: Box, label: "Subflow" },
  { type: "slug_line", icon: Clapperboard, label: "Slug Line" },
];

const isNodeMenu = computed(() => selectedNodeId != null && visible.value);

function onContextMenu(e) {
  e.preventDefault();
  x.value = e.clientX;
  y.value = e.clientY;
  submenu.value = null;
  visible.value = true;
}

function close() {
  visible.value = false;
  submenu.value = null;
}

function addNode(type) {
  live.pushEvent("add_node", { type });
  close();
}

function addAnnotation() {
  live.pushEvent("add_annotation", {});
  close();
}

function duplicateNode() {
  if (selectedNodeId) {
    live.pushEvent("duplicate_node", { id: selectedNodeId });
  }
  close();
}

function deleteNode() {
  if (selectedNodeId) {
    live.pushEvent("delete_node", { id: selectedNodeId });
  }
  close();
}

function copyNodeId() {
  if (selectedNodeId) {
    navigator.clipboard.writeText(String(selectedNodeId));
  }
  close();
}

function autoLayout() {
  live.pushEvent("auto_layout", {});
  close();
}

// Close on click outside or Escape
function onKeydown(e) {
  if (e.key === "Escape") close();
}

function onClickOutside(e) {
  if (visible.value) close();
}

onMounted(() => {
  containerEl?.addEventListener("contextmenu", onContextMenu);
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("pointerdown", onClickOutside);
});

onUnmounted(() => {
  containerEl?.removeEventListener("contextmenu", onContextMenu);
  document.removeEventListener("keydown", onKeydown);
  document.removeEventListener("pointerdown", onClickOutside);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="visible && canEdit"
      class="fixed z-[9999] min-w-[180px] bg-background border border-border rounded-lg shadow-xl py-1 text-sm"
      :style="{ left: `${x}px`, top: `${y}px` }"
      @pointerdown.stop
    >
      <!-- Node context menu -->
      <template v-if="isNodeMenu">
        <button class="cm-item" @click="duplicateNode">
          <Copy class="size-3.5 opacity-60" />
          <span>Duplicate</span>
        </button>
        <button class="cm-item" @click="copyNodeId">
          <Hash class="size-3.5 opacity-60" />
          <span>Copy ID</span>
        </button>
        <div class="h-px bg-border my-1" />
        <button class="cm-item text-destructive" @click="deleteNode">
          <Trash2 class="size-3.5" />
          <span>Delete</span>
        </button>
      </template>

      <!-- Canvas context menu -->
      <template v-else>
        <!-- Add node submenu -->
        <div class="relative" @pointerenter="submenu = 'add'" @pointerleave="submenu = null">
          <button class="cm-item justify-between">
            <span class="flex items-center gap-2">
              <Plus class="size-3.5 opacity-60" />
              <span>Add node</span>
            </span>
            <span class="text-xs opacity-40">▸</span>
          </button>
          <div
            v-if="submenu === 'add'"
            class="absolute left-full top-0 min-w-[180px] bg-background border border-border rounded-lg shadow-xl py-1 -ml-1"
          >
            <button
              v-for="nt in NODE_TYPES"
              :key="nt.type"
              class="cm-item"
              @click="addNode(nt.type)"
            >
              <component :is="nt.icon" class="size-3.5 opacity-60" />
              <span>{{ nt.label }}</span>
            </button>
          </div>
        </div>

        <button class="cm-item" @click="addAnnotation">
          <StickyNote class="size-3.5 opacity-60" />
          <span>Add note</span>
        </button>

        <div class="h-px bg-border my-1" />

        <button class="cm-item" @click="autoLayout">
          <LayoutGrid class="size-3.5 opacity-60" />
          <span>Auto layout</span>
        </button>
      </template>
    </div>
  </Teleport>
</template>

<style scoped>
.cm-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.375rem 0.75rem;
  font-size: 0.8125rem;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.1s;
  background: none;
  border: none;
  color: hsl(var(--foreground));
}

.cm-item:hover {
  background-color: hsl(var(--accent));
}
</style>
