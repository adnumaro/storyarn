<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import type { IDragEvent } from "@vue-dnd-kit/core";
import { inject, ref, useTemplateRef, watch } from "vue";
import { useLive } from "@composables/useLive";
import type { Block, BlockLock } from "../../types";

const isLockedByOther = inject<(id: number | string) => boolean>("isLockedByOther", () => false);
const lockInfo = inject<(id: number | string) => BlockLock | null>("lockInfo", () => null);

import UserAvatar from "@components/layout/UserAvatar.vue";
import BooleanBlock from "../blocks/BooleanBlock.vue";
import DateBlock from "../blocks/DateBlock.vue";
import GalleryBlock from "../blocks/galleryBlock/GalleryBlock.vue";
import MultiSelectBlock from "../blocks/MultiSelectBlock.vue";
import NumberBlock from "../blocks/NumberBlock.vue";
import RichTextBlock from "../blocks/richText/RichTextBlock.vue";
import SelectBlock from "../blocks/SelectBlock.vue";
import TableBlock from "../blocks/table/TableBlock.vue";
import TextBlock from "../blocks/table/TextBlock.vue";
import HorizontalDraggableItem from "./HorizontalDraggableItem.vue";

const blockComponents: Record<string, typeof TextBlock> = {
  text: TextBlock,
  number: NumberBlock,
  boolean: BooleanBlock,
  select: SelectBlock,
  multi_select: MultiSelectBlock,
  date: DateBlock,
  rich_text: RichTextBlock,
  gallery: GalleryBlock,
  table: TableBlock,
};

interface InsertFullWidthPayload {
  draggedBlockId: number | string;
  groupId: string;
  side: string;
  targetBlockId: number | string;
}

const {
  groupId,
  blocks,
  columnCount = 2,
  canEdit = false,
} = defineProps<{
  groupId: string;
  blocks: Block[];
  columnCount?: number;
  canEdit?: boolean;
}>();

const emit = defineEmits<{
  "insert-full-width": [payload: InsertFullWidthPayload];
}>();

const live = useLive();

const localBlocks = ref<Block[]>([...blocks]);
watch(
  () => blocks,
  (v) => {
    localBlocks.value = [...v];
  },
);

const gridRef = useTemplateRef("gridRef");
const columnGroup = `column-${groupId}`;

interface ReorderItem {
  id: number | string;
  column_group_id: string;
  column_index: number;
}

makeDroppable(
  gridRef,
  {
    groups: [columnGroup],
    events: {
      onDrop: (e: IDragEvent) => {
        const result = e.helpers.suggestSort("horizontal");
        if (!result) return;
        localBlocks.value = result.sourceItems as Block[];
        // Push reorder with column indices
        const items: ReorderItem[] = localBlocks.value.map((b, i) => ({
          id: b.id,
          column_group_id: groupId,
          column_index: i,
        }));
        live.pushEvent("reorder_column_group", {
          group_id: groupId,
          items,
        });
      },
    },
  },
  () => localBlocks.value,
);

function resolveComponent(type: string): typeof TextBlock | null {
  return blockComponents[type] || null;
}

function gridClass(): string {
  if (columnCount === 2) return "sm:grid-cols-2";
  if (columnCount === 3) return "sm:grid-cols-3";
  return "sm:grid-cols-1";
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
      <div class="relative">
        <component
          :is="resolveComponent(block.type)"
          :block="block"
          :can-edit="canEdit && !isLockedByOther(block.id)"
        >
          <template v-if="isLockedByOther(block.id)" #menu>
            <UserAvatar
              :email="lockInfo(block.id)?.userEmail"
              :color="lockInfo(block.id)?.userColor"
              size="xs"
            />
          </template>
        </component>
        <div
          v-if="isLockedByOther(block.id)"
          class="absolute inset-0 rounded-lg border-2 pointer-events-none"
          :style="{ borderColor: lockInfo(block.id)?.userColor }"
        />
      </div>
    </HorizontalDraggableItem>
  </div>
</template>
