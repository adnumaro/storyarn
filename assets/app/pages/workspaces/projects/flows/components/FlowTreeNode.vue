<script setup>
import { makeDraggable, makeDroppable } from "@vue-dnd-kit/core";
import { ChevronRight, FilePlus, GitBranch, Star, Trash2 } from "lucide-vue-next";
import { computed, onMounted, onUnmounted, ref, useTemplateRef, watch } from "vue";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@components/ui/context-menu/index.js";

const { node, index, siblings, selectedFlowId, canEdit, depth, searchActive, flowHref } =
  defineProps({
    node: { type: Object, required: true },
    index: { type: Number, required: true },
    siblings: { type: Array, required: true },
    selectedFlowId: { type: [String, Number], default: null },
    canEdit: { type: Boolean, default: false },
    depth: { type: Number, default: 0 },
    searchActive: { type: Boolean, default: false },
    flowHref: { type: Function, required: true },
  });

const emit = defineEmits(["createChild", "requestDelete", "setMain", "drop"]);

const hasChildren = computed(() => node.children && node.children.length > 0);

const isSelected = computed(
  () => selectedFlowId != null && String(node.id) === String(selectedFlowId),
);

// Auto-expand
function hasSelectedDescendant(node, selectedId) {
  if (!selectedId || !node.children) return false;
  for (const child of node.children) {
    if (String(child.id) === String(selectedId)) return true;
    if (hasSelectedDescendant(child, selectedId)) return true;
  }
  return false;
}

const shouldAutoExpand = computed(
  () => hasChildren.value && hasSelectedDescendant(node, selectedFlowId),
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

function onToggle() {
  userToggled.value = true;
  isOpen.value = !isOpen.value;
}

const paddingLeft = computed(() => `${depth * 12 + 4}px`);

// Draggable
const rowRef = useTemplateRef("rowRef");

const { isDragging, isDragOver: rowPlacement } = makeDraggable(
  rowRef,
  { activation: { distance: 5 } },
  () => [index, siblings],
);

// Center zone detection
const pointerZone = ref(null);
const CENTER_THRESHOLD = 0.3;

function onPointerMove(e) {
  const el = rowRef.value;
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

// Droppable children container
const childrenRef = useTemplateRef("childrenRef");

const { isDragOver: childrenOver } = makeDroppable(
  childrenRef,
  { events: { onDrop: (e) => emit("drop", e) } },
  () => node.children,
);

// Auto-expand on hover during drag
let autoExpandTimer = null;

watch([() => childrenOver.value, pointerZone], ([childOver, zone]) => {
  clearTimeout(autoExpandTimer);
  if ((childOver || zone === "nest") && hasChildren.value && !isOpen.value) {
    autoExpandTimer = setTimeout(() => {
      isOpen.value = true;
    }, 600);
  }
});
</script>

<template>
  <div :class="{ 'opacity-30': isDragging }">
    <!-- Drop indicator: before -->
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

          <!-- Flow link -->
          <a :href="flowHref(node)" class="flex-1 flex items-center gap-1.5 py-1.5 min-w-0">
            <GitBranch class="size-3.5 shrink-0 opacity-50" />
            <span class="truncate">{{ node.name }}</span>
            <Star v-if="node.is_main" class="size-3 shrink-0 text-amber-500 fill-amber-500" />
          </a>

          <!-- Hover actions -->
          <div
            v-if="canEdit"
            class="shrink-0 flex items-center opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <button
              type="button"
              class="size-5 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground hover:text-foreground"
              title="Add child flow"
              @click.stop.prevent="emit('createChild', node.id)"
            >
              <FilePlus class="size-3" />
            </button>
            <button
              type="button"
              class="size-5 inline-flex items-center justify-center rounded hover:bg-destructive/10 text-muted-foreground hover:text-destructive"
              title="Move to Trash"
              @click.stop.prevent="emit('requestDelete', node)"
            >
              <Trash2 class="size-3" />
            </button>
          </div>
        </div>
      </ContextMenuTrigger>

      <ContextMenuContent v-if="canEdit">
        <ContextMenuItem
          v-if="!node.is_main"
          class="gap-2 text-xs"
          @select="emit('setMain', node.id)"
        >
          <Star class="size-3.5" />
          Set as main
        </ContextMenuItem>
        <ContextMenuItem class="gap-2 text-xs" @select="emit('createChild', node.id)">
          <FilePlus class="size-3.5" />
          Add child flow
        </ContextMenuItem>
        <ContextMenuItem
          class="gap-2 text-xs text-destructive"
          @select="emit('requestDelete', node)"
        >
          <Trash2 class="size-3.5" />
          Move to Trash
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>

    <!-- Drop indicator: after -->
    <div
      v-if="pointerZone === 'after'"
      class="h-0.5 bg-primary rounded-full pointer-events-none"
      :style="{ marginLeft: paddingLeft }"
      aria-hidden
    />

    <!-- Children drop zone -->
    <div
      ref="childrenRef"
      v-show="isOpen || !hasChildren"
      :class="['min-h-[2px] transition-colors', childrenOver && 'bg-primary/5']"
    >
      <FlowTreeNode
        v-for="(child, childIndex) in node.children"
        :key="child.id"
        :node="child"
        :index="childIndex"
        :siblings="node.children"
        :selected-flow-id="selectedFlowId"
        :can-edit="canEdit"
        :depth="depth + 1"
        :search-active="searchActive"
        :flow-href="flowHref"
        @create-child="(id) => emit('createChild', id)"
        @request-delete="(flow) => emit('requestDelete', flow)"
        @set-main="(id) => emit('setMain', id)"
        @drop="(e) => emit('drop', e)"
      />
    </div>
  </div>
</template>
