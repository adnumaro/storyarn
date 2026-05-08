<script setup lang="ts">
import { makeDraggable, makeDroppable } from "@vue-dnd-kit/core";
import { ChevronRight, FilePlus, FileText, Trash2 } from "lucide-vue-next";
import { computed, onMounted, onUnmounted, ref, useTemplateRef, watch } from "vue";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@components/ui/context-menu";
import type { SheetTreeNodeData } from "../../../types";

const {
  node,
  index,
  siblings,
  selectedSheetId = null,
  canEdit = false,
  depth = 0,
  searchActive = false,
  sheetHref,
} = defineProps<{
  node: SheetTreeNodeData;
  index: number;
  siblings: SheetTreeNodeData[];
  selectedSheetId?: string | number | null;
  canEdit?: boolean;
  depth?: number;
  searchActive?: boolean;
  sheetHref: (node: SheetTreeNodeData) => string;
}>();

const emit = defineEmits<{
  createChild: [id: number | string];
  requestDelete: [node: SheetTreeNodeData];
  drop: [event: unknown];
}>();

const hasChildren = computed(() => node.children && node.children.length > 0);

const isSelected = computed(
  () => selectedSheetId != null && String(node.id) === String(selectedSheetId),
);

// ── Auto-expand ──
function hasSelectedDescendant(
  node: SheetTreeNodeData,
  selectedId: string | number | null | undefined,
): boolean {
  if (!selectedId || !node.children) return false;
  for (const child of node.children) {
    if (String(child.id) === String(selectedId)) return true;
    if (hasSelectedDescendant(child, selectedId)) return true;
  }
  return false;
}

const shouldAutoExpand = computed(
  () => hasChildren.value && hasSelectedDescendant(node, selectedSheetId),
);

const userToggled = ref(false);
const isOpen = ref(shouldAutoExpand.value);

watch(
  () => searchActive,
  (active) => {
    if (active) isOpen.value = true;
    else if (!userToggled.value) isOpen.value = shouldAutoExpand.value;
  },
);

// Auto-expand when a descendant becomes selected (e.g., after creating a
// child sheet with the parent collapsed). Overrides a prior manual collapse
// so the user can see the newly opened/created sheet.
watch(shouldAutoExpand, (should) => {
  if (should) isOpen.value = true;
});

function onToggle(): void {
  userToggled.value = true;
  isOpen.value = !isOpen.value;
}

const avatarUrl = computed(() => node.avatar_url || null);
const paddingLeft = computed(() => `${depth * 12 + 4}px`);

// ── Draggable: the node row ──
const rowRef = useTemplateRef("rowRef");

const { isDragging, isDragOver: rowPlacement } = makeDraggable(
  rowRef,
  { activation: { distance: 5 } },
  () => [index, siblings],
);

// Manual center zone detection (avoids dual-role routing issues)
const pointerZone = ref<"before" | "nest" | "after" | null>(null);
const CENTER_THRESHOLD = 0.3;

function onPointerMove(e: PointerEvent): void {
  const el = rowRef.value as HTMLElement | null;
  if (!el || !rowPlacement.value) {
    pointerZone.value = null;
    return;
  }
  const rect = el.getBoundingClientRect();
  const relY = (e.clientY - rect.top) / rect.height;
  if (relY <= CENTER_THRESHOLD) pointerZone.value = "before";
  else if (relY >= 1 - CENTER_THRESHOLD) pointerZone.value = "after";
  else pointerZone.value = "nest";
}

onMounted(() => document.addEventListener("pointermove", onPointerMove));
onUnmounted(() => document.removeEventListener("pointermove", onPointerMove));

watch(rowPlacement, (p) => {
  if (!p) pointerZone.value = null;
});

// ── Droppable: the children container (for nesting) ──
const childrenRef = useTemplateRef("childrenRef");

const { isDragOver: childrenOver } = makeDroppable(
  childrenRef,
  { events: { onDrop: (e: unknown) => emit("drop", e) } },
  () => node.children ?? [],
);

// Auto-expand on hover during drag (600ms)
let autoExpandTimer: ReturnType<typeof setTimeout> | null = null;

watch([() => childrenOver.value, pointerZone], ([childOver, zone]) => {
  if (autoExpandTimer) clearTimeout(autoExpandTimer);
  if ((childOver || zone === "nest") && hasChildren.value && !isOpen.value) {
    autoExpandTimer = setTimeout(() => {
      isOpen.value = true;
    }, 600);
  }
});
</script>

<template>
  <div :class="{ 'opacity-30': isDragging }">
    <!-- Drop indicator: before (sibling) -->
    <div
      v-if="pointerZone === 'before'"
      class="h-0.5 bg-primary rounded-full pointer-events-none"
      :style="{ marginLeft: paddingLeft }"
      aria-hidden
    />

    <ContextMenu>
      <ContextMenuTrigger as-child>
        <div
          ref="rowRef"
          :class="[
            'group flex items-center gap-1 pr-1 rounded-md text-sm transition-colors cursor-default',
            isSelected
              ? 'bg-accent text-accent-foreground font-medium'
              : pointerZone === 'nest'
                ? 'bg-primary/10 ring-1 ring-primary/30'
                : 'text-foreground/80 hover:bg-accent/50',
          ]"
          :style="{ paddingLeft }"
        >
          <!-- Expand toggle -->
          <button
            v-if="hasChildren"
            type="button"
            class="shrink-0 size-5 inline-flex items-center justify-center rounded hover:bg-accent"
            @click.stop.prevent="onToggle"
          >
            <ChevronRight :class="['size-3 transition-transform', isOpen && 'rotate-90']" />
          </button>
          <span v-else class="shrink-0 size-5" />

          <!-- Sheet link -->
          <a
            :href="sheetHref(node)"
            data-phx-link="patch"
            data-phx-link-state="push"
            class="flex-1 flex items-center gap-1.5 py-1.5 min-w-0"
          >
            <img
              v-if="avatarUrl"
              :src="avatarUrl"
              :alt="node.name"
              class="size-4 rounded shrink-0 object-cover"
            />
            <FileText v-else class="size-3.5 shrink-0 opacity-50" />
            <span class="truncate">{{ node.name }}</span>
          </a>

          <!-- Hover actions -->
          <div
            v-if="canEdit"
            class="shrink-0 flex items-center opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <button
              type="button"
              class="size-5 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground hover:text-foreground"
              :title="$t('sheets.tree.add_child')"
              @click.stop.prevent="emit('createChild', node.id)"
            >
              <FilePlus class="size-3" />
            </button>
            <button
              type="button"
              class="size-5 inline-flex items-center justify-center rounded hover:bg-destructive/10 text-muted-foreground hover:text-destructive"
              :title="$t('sheets.tree.move_to_trash')"
              @click.stop.prevent="emit('requestDelete', node)"
            >
              <Trash2 class="size-3" />
            </button>
          </div>
        </div>
      </ContextMenuTrigger>

      <ContextMenuContent v-if="canEdit" class="">
        <ContextMenuItem class="gap-2 text-xs" @select="emit('createChild', node.id)">
          <FilePlus class="size-3.5" />
          {{ $t("sheets.tree.add_child") }}
        </ContextMenuItem>
        <ContextMenuItem
          class="gap-2 text-xs text-destructive"
          @select="emit('requestDelete', node)"
        >
          <Trash2 class="size-3.5" />
          {{ $t("sheets.tree.move_to_trash") }}
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>

    <!-- Drop indicator: after (sibling) -->
    <div
      v-if="pointerZone === 'after'"
      class="h-0.5 bg-primary rounded-full pointer-events-none"
      :style="{ marginLeft: paddingLeft }"
      aria-hidden
    />

    <!-- Children drop zone — v-show keeps DOM mounted so makeDroppable stays registered -->
    <div
      ref="childrenRef"
      v-show="isOpen || !hasChildren"
      :class="['min-h-0.5 transition-colors', childrenOver && 'bg-primary/5']"
    >
      <SheetTreeNode
        v-for="(child, childIndex) in node.children"
        :key="child.id"
        :node="child"
        :index="childIndex"
        :siblings="node.children!"
        :selected-sheet-id="selectedSheetId"
        :can-edit="canEdit"
        :depth="depth + 1"
        :search-active="searchActive"
        :sheet-href="sheetHref"
        @create-child="(id) => emit('createChild', id)"
        @request-delete="(sheet) => emit('requestDelete', sheet)"
        @drop="(e) => emit('drop', e)"
      />
    </div>
  </div>
</template>
