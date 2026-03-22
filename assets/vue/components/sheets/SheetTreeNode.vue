<script setup>
import { ref, computed, watch, onMounted, onUnmounted, useTemplateRef } from "vue"
import { makeDraggable, makeDroppable } from "@vue-dnd-kit/core"
import { FileText, ChevronRight, Trash2, FilePlus } from "lucide-vue-next"
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@/vue/components/ui/context-menu"

const props = defineProps({
  node: { type: Object, required: true },
  index: { type: Number, required: true },
  siblings: { type: Array, required: true },
  selectedSheetId: { type: [String, Number], default: null },
  canEdit: { type: Boolean, default: false },
  depth: { type: Number, default: 0 },
  searchActive: { type: Boolean, default: false },
  sheetHref: { type: Function, required: true },
})

const emit = defineEmits(["createChild", "requestDelete", "drop"])

const hasChildren = computed(
  () => props.node.children && props.node.children.length > 0,
)

const isSelected = computed(
  () => props.selectedSheetId != null && String(props.node.id) === String(props.selectedSheetId),
)

// ── Auto-expand ──
function hasSelectedDescendant(node, selectedId) {
  if (!selectedId || !node.children) return false
  for (const child of node.children) {
    if (String(child.id) === String(selectedId)) return true
    if (hasSelectedDescendant(child, selectedId)) return true
  }
  return false
}

const shouldAutoExpand = computed(() =>
  hasChildren.value && hasSelectedDescendant(props.node, props.selectedSheetId)
)

const userToggled = ref(false)
const isOpen = ref(shouldAutoExpand.value)

watch(
  () => props.searchActive,
  (active) => {
    if (active) isOpen.value = true
    else if (!userToggled.value) isOpen.value = shouldAutoExpand.value
  },
)

function onToggle() {
  userToggled.value = true
  isOpen.value = !isOpen.value
}

const avatarUrl = computed(() => props.node.avatar_url || null)
const paddingLeft = computed(() => `${props.depth * 12 + 4}px`)

// ── Draggable: the node row ──
const rowRef = useTemplateRef("rowRef")

const { isDragging, isDragOver: rowPlacement } = makeDraggable(
  rowRef,
  { activation: { distance: 5 } },
  () => [props.index, props.siblings],
)

// Manual center zone detection (avoids dual-role routing issues)
const pointerZone = ref(null) // "before" | "nest" | "after" | null
const CENTER_THRESHOLD = 0.3

function onPointerMove(e) {
  const el = rowRef.value
  if (!el || !rowPlacement.value) { pointerZone.value = null; return }
  const rect = el.getBoundingClientRect()
  const relY = (e.clientY - rect.top) / rect.height
  if (relY <= CENTER_THRESHOLD) pointerZone.value = "before"
  else if (relY >= 1 - CENTER_THRESHOLD) pointerZone.value = "after"
  else pointerZone.value = "nest"
}

onMounted(() => document.addEventListener("pointermove", onPointerMove))
onUnmounted(() => document.removeEventListener("pointermove", onPointerMove))

watch(rowPlacement, (p) => { if (!p) pointerZone.value = null })

// ── Droppable: the children container (for nesting) ──
const childrenRef = useTemplateRef("childrenRef")

const { isDragOver: childrenOver } = makeDroppable(
  childrenRef,
  { events: { onDrop: (e) => emit("drop", e) } },
  () => props.node.children,
)

// Auto-expand on hover during drag (600ms)
let autoExpandTimer = null

watch(
  [() => childrenOver.value, pointerZone],
  ([childOver, zone]) => {
    clearTimeout(autoExpandTimer)
    if ((childOver || zone === "nest") && hasChildren.value && !isOpen.value) {
      autoExpandTimer = setTimeout(() => {
        isOpen.value = true
      }, 600)
    }
  },
)
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
            'group flex items-center gap-1 rounded-md text-sm transition-colors cursor-default',
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
            <ChevronRight
              :class="['size-3 transition-transform', isOpen && 'rotate-90']"
            />
          </button>
          <span v-else class="shrink-0 size-5" />

          <!-- Sheet link -->
          <a
            :href="sheetHref(node)"
            class="flex-1 flex items-center gap-1.5 py-1.5 pr-2 min-w-0"
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
        </div>
      </ContextMenuTrigger>

      <ContextMenuContent v-if="canEdit" class="z-[1040]">
        <ContextMenuItem class="gap-2 text-xs" @select="emit('createChild', node.id)">
          <FilePlus class="size-3.5" />
          Add child sheet
        </ContextMenuItem>
        <ContextMenuItem class="gap-2 text-xs text-destructive" @select="emit('requestDelete', node)">
          <Trash2 class="size-3.5" />
          Move to Trash
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
      :class="['min-h-[2px] transition-colors', childrenOver && 'bg-primary/5']"
    >
      <SheetTreeNode
        v-for="(child, childIndex) in node.children"
        :key="child.id"
        :node="child"
        :index="childIndex"
        :siblings="node.children"
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
