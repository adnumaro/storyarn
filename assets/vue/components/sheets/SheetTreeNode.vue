<script setup>
import { ref, computed, watch } from "vue"
import { FileText, ChevronRight, Trash2, FilePlus } from "lucide-vue-next"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/vue/components/ui/collapsible"
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@/vue/components/ui/context-menu"

const props = defineProps({
  node: { type: Object, required: true },
  selectedSheetId: { type: [String, Number], default: null },
  canEdit: { type: Boolean, default: false },
  depth: { type: Number, default: 0 },
  searchActive: { type: Boolean, default: false },
  sheetHref: { type: Function, required: true },
})

const emit = defineEmits(["createChild", "requestDelete"])

const hasChildren = computed(
  () => props.node.children && props.node.children.length > 0,
)

const isSelected = computed(
  () => props.selectedSheetId != null && String(props.node.id) === String(props.selectedSheetId),
)

// Auto-expand only if this node contains the selected sheet (recursive check)
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

// Start collapsed by default, auto-expand only if contains selected
const userToggled = ref(false)
const isOpen = ref(shouldAutoExpand.value)

// When searching, force expand; when search clears, restore
watch(
  () => props.searchActive,
  (active) => {
    if (active) isOpen.value = true
    else if (!userToggled.value) isOpen.value = shouldAutoExpand.value
  },
)

// Track manual toggle
function onToggle(open) {
  userToggled.value = true
  isOpen.value = open
}

const avatarUrl = computed(() => {
  // Check for avatar_url in blocks (first gallery/reference block with an image)
  return props.node.avatar_url || null
})

const paddingLeft = computed(() => `${props.depth * 12 + 4}px`)
</script>

<template>
  <Collapsible :open="isOpen" @update:open="onToggle">
    <ContextMenu>
      <ContextMenuTrigger as-child>
        <div
          :class="[
            'group flex items-center gap-1 rounded-md text-sm transition-colors',
            isSelected
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-foreground/80 hover:bg-accent/50',
          ]"
          :style="{ paddingLeft }"
        >
          <!-- Expand toggle -->
          <CollapsibleTrigger v-if="hasChildren" as-child>
            <button
              type="button"
              class="shrink-0 size-5 inline-flex items-center justify-center rounded hover:bg-accent"
            >
              <ChevronRight
                :class="['size-3 transition-transform', isOpen && 'rotate-90']"
              />
            </button>
          </CollapsibleTrigger>
          <span v-else class="shrink-0 size-5" />

          <!-- Sheet link -->
          <a
            :href="sheetHref(node)"
            class="flex-1 flex items-center gap-1.5 py-1.5 pr-2 min-w-0"
          >
            <!-- Avatar or icon -->
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

      <!-- Context menu (only if can edit) -->
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

    <!-- Children (recursive) -->
    <CollapsibleContent v-if="hasChildren">
      <SheetTreeNode
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :selected-sheet-id="selectedSheetId"
        :can-edit="canEdit"
        :depth="depth + 1"
        :search-active="searchActive"
        :sheet-href="sheetHref"
        @create-child="(id) => emit('createChild', id)"
        @request-delete="(sheet) => emit('requestDelete', sheet)"
      />
    </CollapsibleContent>
  </Collapsible>
</template>
