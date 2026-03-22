<script setup>
import { ref, onMounted, onUnmounted, provide } from "vue"
import { useLive } from "@/vue/composables/useLive"
import { ArrowUpRight, MoreHorizontal, Trash2, Link2Off, Link2 } from "lucide-vue-next"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu"
import { DnDProvider } from "@vue-dnd-kit/core"
import AddBlockMenu from "./AddBlockMenu.vue"
import SortableBlockList from "./SortableBlockList.vue"

// Block type components (for inherited blocks, rendered without sortable)
import TextBlock from "./blocks/TextBlock.vue"
import NumberBlock from "./blocks/NumberBlock.vue"
import BooleanBlock from "./blocks/BooleanBlock.vue"
import SelectBlock from "./blocks/SelectBlock.vue"
import MultiSelectBlock from "./blocks/MultiSelectBlock.vue"
import DateBlock from "./blocks/DateBlock.vue"
import RichTextBlock from "./blocks/RichTextBlock.vue"
import GalleryBlock from "./blocks/GalleryBlock.vue"

const blockComponents = {
  text: TextBlock,
  number: NumberBlock,
  boolean: BooleanBlock,
  select: SelectBlock,
  multi_select: MultiSelectBlock,
  date: DateBlock,
  rich_text: RichTextBlock,
  gallery: GalleryBlock,
}

const props = defineProps({
  blocks: { type: Array, default: () => [] },
  inheritedGroups: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  workspaceSlug: { type: String, default: "" },
  projectSlug: { type: String, default: "" },
})

const live = useLive()

// ── Block selection ──
const selectedBlockId = ref(null)

function selectBlock(id) {
  selectedBlockId.value = selectedBlockId.value === id ? null : id
}

function deselectBlock() {
  selectedBlockId.value = null
}

provide("selectedBlockId", selectedBlockId)
provide("selectBlock", selectBlock)

function isInputFocused() {
  const el = document.activeElement
  if (!el) return false
  const tag = el.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable
}

function onKeydown(e) {
  if (!selectedBlockId.value || !props.canEdit || isInputFocused()) return

  if (e.key === "Backspace" || e.key === "Delete") {
    e.preventDefault()
    live.pushEvent("delete_block", { id: selectedBlockId.value })
    selectedBlockId.value = null
  }

  if ((e.metaKey || e.ctrlKey) && e.key === "d") {
    e.preventDefault()
    live.pushEvent("duplicate_block", { id: selectedBlockId.value })
  }

  if (e.key === "Escape") {
    deselectBlock()
  }
}

onMounted(() => document.addEventListener("keydown", onKeydown))
onUnmounted(() => document.removeEventListener("keydown", onKeydown))

function addBlock(type) {
  live.pushEvent("add_block", { type })
}

function deleteBlock(id) {
  live.pushEvent("delete_block", { id })
}

function detachBlock(id) {
  live.pushEvent("detach_block", { id })
}

function reattachBlock(id) {
  live.pushEvent("reattach_block", { id })
}

function resolveComponent(type) {
  return blockComponents[type] || null
}
</script>

<template>
  <DnDProvider>
    <div class="space-y-3">
      <!-- ═══ INHERITED BLOCKS (grouped by source sheet) ═══ -->
      <div v-for="group in inheritedGroups" :key="group.sourceSheet.id" class="mb-4">
        <div class="flex items-center gap-2 mb-2 text-xs text-muted-foreground uppercase tracking-wider">
          <ArrowUpRight class="size-3 text-blue-400" />
          <span>Inherited from</span>
          <a
            :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/v2/sheets/${group.sourceSheet.id}`"
            class="text-primary hover:underline font-medium normal-case"
          >
            {{ group.sourceSheet.name }}
          </a>
          <span class="text-muted-foreground/50">({{ group.blocks.length }})</span>
        </div>

        <div class="border-l-2 border-blue-400/30 ml-1 pl-3 space-y-3">
          <component
            v-for="block in group.blocks"
            :key="block.id"
            :is="resolveComponent(block.type)"
            :block="block"
            :can-edit="canEdit"
            :inherited="true"
          >
            <template #menu>
              <DropdownMenu v-if="canEdit">
                <DropdownMenuTrigger as-child>
                  <button class="size-6 rounded flex items-center justify-center text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity hover:bg-accent">
                    <MoreHorizontal class="size-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" class="z-[1030]">
                  <DropdownMenuItem v-if="!block.detached" class="gap-2 text-xs" @select="detachBlock(block.id)">
                    <Link2Off class="size-3.5" />
                    Detach from parent
                  </DropdownMenuItem>
                  <DropdownMenuItem v-if="block.detached" class="gap-2 text-xs" @select="reattachBlock(block.id)">
                    <Link2 class="size-3.5" />
                    Reattach to parent
                  </DropdownMenuItem>
                  <DropdownMenuSeparator v-if="block.detached" />
                  <DropdownMenuItem v-if="block.detached" class="text-destructive gap-2 text-xs" @select="deleteBlock(block.id)">
                    <Trash2 class="size-3.5" />
                    Delete block
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </template>
          </component>
        </div>
      </div>

      <!-- ═══ OWN PROPERTIES SEPARATOR ═══ -->
      <div v-if="inheritedGroups.length > 0" class="flex items-center gap-3 py-2">
        <div class="h-px flex-1 bg-border" />
        <span class="text-xs text-muted-foreground uppercase tracking-wider">Own properties</span>
        <div class="h-px flex-1 bg-border" />
      </div>

      <!-- ═══ OWN BLOCKS (sortable) ═══ -->
      <SortableBlockList :layout-items="blocks" :can-edit="canEdit" />

      <div v-if="blocks.length === 0 && inheritedGroups.length === 0 && !canEdit" class="py-8 text-center text-sm text-muted-foreground">
        No blocks yet.
      </div>

      <AddBlockMenu v-if="canEdit" @select="addBlock" />
    </div>
  </DnDProvider>
</template>
