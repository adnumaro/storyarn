<script setup>
import { ref, useTemplateRef, watch } from "vue"
import { useLive } from "@/vue/composables/useLive"
import { makeDroppable } from "@vue-dnd-kit/core"

import HorizontalDraggableItem from "./HorizontalDraggableItem.vue"
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
  groupId: { type: String, required: true },
  blocks: { type: Array, required: true },
  columnCount: { type: Number, default: 2 },
  canEdit: { type: Boolean, default: false },
})

const emit = defineEmits(["insert-full-width"])

const live = useLive()

const localBlocks = ref([...props.blocks])
watch(() => props.blocks, (v) => { localBlocks.value = [...v] })

const gridRef = useTemplateRef("gridRef")
const columnGroup = `column-${props.groupId}`

makeDroppable(gridRef, {
  groups: [columnGroup],
  events: {
    onDrop: (e) => {
      const result = e.helpers.suggestSort("horizontal")
      if (!result) return
      localBlocks.value = result.sourceItems
      // Push reorder with column indices
      const items = localBlocks.value.map((b, i) => ({
        id: b.id,
        column_group_id: props.groupId,
        column_index: i,
      }))
      live.pushEvent("reorder_column_group", { group_id: props.groupId, items })
    },
  },
}, () => localBlocks.value)

function resolveComponent(type) {
  return blockComponents[type] || null
}

function gridClass() {
  if (props.columnCount === 2) return "sm:grid-cols-2"
  if (props.columnCount === 3) return "sm:grid-cols-3"
  return "sm:grid-cols-1"
}
</script>

<template>
  <div ref="gridRef" :class="['grid gap-6', gridClass()]">
    <HorizontalDraggableItem
      v-for="(block, index) in localBlocks"
      :key="block.id"
      :block-id="block.id"
      :group-id="groupId"
      :index="index"
      :items="localBlocks"
      :can-edit="canEdit"
      :group="columnGroup"
      @insert-full-width="(payload) => emit('insert-full-width', payload)"
    >
      <component
        :is="resolveComponent(block.type)"
        :block="block"
        :can-edit="canEdit"
      />
    </HorizontalDraggableItem>
  </div>
</template>
