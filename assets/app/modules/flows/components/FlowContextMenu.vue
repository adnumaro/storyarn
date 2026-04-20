<script setup lang="ts">
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
import type { Component } from "vue";
import { computed, nextTick, onMounted, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useLive } from "@composables/useLive";

interface NodeTypeEntry {
  type: string;
  icon: Component;
  label: string;
}

const {
  containerEl = null,
  canEdit = false,
  selectedNodeId = null,
  selectedNodeType = null,
} = defineProps<{
  containerEl: HTMLElement | null;
  canEdit: boolean;
  selectedNodeId: number | string | null;
  selectedNodeType: string | null;
}>();

const { t } = useI18n();
const live = useLive();
const visible = ref(false);
const x = ref(0);
const y = ref(0);
const submenu = ref<string | null>(null);

const NODE_TYPES = computed<NodeTypeEntry[]>(() => [
  { type: "dialogue", icon: MessageSquare, label: t("flows.node_types.dialogue") },
  { type: "condition", icon: GitBranch, label: t("flows.node_types.condition") },
  { type: "instruction", icon: Zap, label: t("flows.node_types.instruction") },
  { type: "hub", icon: LogIn, label: t("flows.node_types.hub") },
  { type: "jump", icon: LogOut, label: t("flows.node_types.jump") },
  { type: "exit", icon: ArrowRightToLine, label: t("flows.node_types.exit") },
  { type: "subflow", icon: Box, label: t("flows.node_types.subflow") },
]);

const isNodeMenu = computed(() => selectedNodeId != null && visible.value);

function onContextMenu(e: MouseEvent): void {
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

function addNode(type: string): void {
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

function createSequenceFromNode() {
  if (selectedNodeId) {
    live.pushEvent("create_sequence_from_node", { node_id: selectedNodeId });
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
function onKeydown(e: KeyboardEvent): void {
  if (e.key === "Escape") close();
}

function onClickOutside(_e: PointerEvent): void {
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
      class="fixed z-9999 min-w-45 bg-background border border-border rounded-lg shadow-xl py-1 text-sm"
      :style="{ left: `${x}px`, top: `${y}px` }"
      @pointerdown.stop
    >
      <!-- Node context menu -->
      <template v-if="isNodeMenu">
        <button class="cm-item" @click="duplicateNode">
          <Copy class="size-3.5 opacity-60" />
          <span>{{ $t("flows.context_menu.duplicate") }}</span>
        </button>
        <button class="cm-item" @click="copyNodeId">
          <Hash class="size-3.5 opacity-60" />
          <span>{{ $t("flows.context_menu.copy_id") }}</span>
        </button>
        <div class="h-px bg-border my-1" />
        <button class="cm-item" @click="createSequenceFromNode">
          <Clapperboard class="size-3.5 opacity-60" />
          <span>{{ $t("flows.context_menu.create_sequence") }}</span>
        </button>
        <div class="h-px bg-border my-1" />
        <button class="cm-item text-destructive" @click="deleteNode">
          <Trash2 class="size-3.5" />
          <span>{{ $t("flows.context_menu.delete") }}</span>
        </button>
      </template>

      <!-- Canvas context menu -->
      <template v-else>
        <!-- Add node submenu -->
        <div class="relative" @pointerenter="submenu = 'add'" @pointerleave="submenu = null">
          <button class="cm-item justify-between">
            <span class="flex items-center gap-2">
              <Plus class="size-3.5 opacity-60" />
              <span>{{ $t("flows.context_menu.add_node") }}</span>
            </span>
            <span class="text-xs opacity-40">▸</span>
          </button>
          <div
            v-if="submenu === 'add'"
            class="absolute left-full top-0 min-w-45 bg-background border border-border rounded-lg shadow-xl py-1 -ml-1"
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
          <span>{{ $t("flows.context_menu.add_note") }}</span>
        </button>

        <div class="h-px bg-border my-1" />

        <button class="cm-item" @click="autoLayout">
          <LayoutGrid class="size-3.5 opacity-60" />
          <span>{{ $t("flows.context_menu.auto_layout") }}</span>
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
