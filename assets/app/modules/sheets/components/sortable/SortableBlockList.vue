<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import type { IDragEvent } from "@vue-dnd-kit/core";
import { Link2 } from "lucide-vue-next";
import { inject, ref, useTemplateRef, watch } from "vue";
import UserAvatar from "@components/layout/UserAvatar.vue";
import { useLive } from "@composables/useLive";
import type {
  Block,
  BlockLock,
  ColumnGroupLayoutItem,
  FullWidthLayoutItem,
  LayoutItem,
} from "../../types";
import DraggableBlock from "./DraggableBlock.vue";
import SortableColumnGroup from "./SortableColumnGroup.vue";

const isLockedByOther = inject<(id: number | string) => boolean>("isLockedByOther", () => false);
const lockInfo = inject<(id: number | string) => BlockLock | null>("lockInfo", () => null);

import BooleanBlock from "../blocks/BooleanBlock.vue";
import DateBlock from "../blocks/DateBlock.vue";
import GalleryBlock from "../blocks/galleryBlock/GalleryBlock.vue";
import MultiSelectBlock from "../blocks/MultiSelectBlock.vue";
import NumberBlock from "../blocks/NumberBlock.vue";
import ReferenceBlock from "../blocks/ReferenceBlock.vue";
import RichTextBlock from "../blocks/richText/RichTextBlock.vue";
import SelectBlock from "../blocks/SelectBlock.vue";
import TableBlock from "../blocks/table/TableBlock.vue";
// Block type components
import TextBlock from "../blocks/table/TextBlock.vue";

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
  reference: ReferenceBlock,
};

const { layoutItems = [], canEdit = false } = defineProps<{
  /** Layout items: [{type:"full_width", block:{...}}, {type:"column_group", group_id, blocks:[...], column_count}] */
  layoutItems?: LayoutItem[];
  canEdit?: boolean;
}>();

const live = useLive();

function reattachBlock(id: number | string): void {
  live.pushEvent("reattach_block", { id });
}

const localItems = ref<LayoutItem[]>([...layoutItems]);
watch(
  () => layoutItems,
  (v) => {
    localItems.value = [...v];
  },
);

interface SerializedLayoutEntry {
  column_group_id: string | null;
  column_index: number;
  id: number | string;
}

function serializeLayout(items: LayoutItem[]): SerializedLayoutEntry[] {
  const entries: SerializedLayoutEntry[] = [];
  for (const item of items) {
    if (item.type === "column_group") {
      for (let index = 0; index < item.blocks.length; index++) {
        entries.push({
          column_group_id: item.group_id,
          column_index: index,
          id: item.blocks[index].id,
        });
      }
    } else {
      entries.push({
        column_group_id: null,
        column_index: 0,
        id: item.block.id,
      });
    }
  }
  return entries;
}

function pushColumnLayout(items: LayoutItem[]): void {
  live.pushEvent("reorder_with_columns", { items: serializeLayout(items) });
}

function removeFullWidthItem(items: LayoutItem[], blockId: number | string): LayoutItem[] {
  return items.filter(
    (item) => !(item.type === "full_width" && (item as FullWidthLayoutItem).block.id === blockId),
  );
}

function createColumnGroupItems(
  items: LayoutItem[],
  draggedBlockId: number | string,
  targetBlockId: number | string,
  side: string,
): LayoutItem[] | null {
  if (draggedBlockId === targetBlockId) return null;

  const draggedItem = items.find(
    (item) =>
      item.type === "full_width" && (item as FullWidthLayoutItem).block.id === draggedBlockId,
  ) as FullWidthLayoutItem | undefined;
  const targetItem = items.find(
    (item) =>
      item.type === "full_width" && (item as FullWidthLayoutItem).block.id === targetBlockId,
  ) as FullWidthLayoutItem | undefined;

  if (!draggedItem || !targetItem) return null;

  const nextItems = removeFullWidthItem(items, draggedBlockId);
  const targetIndex = nextItems.findIndex(
    (item) =>
      item.type === "full_width" && (item as FullWidthLayoutItem).block.id === targetBlockId,
  );

  if (targetIndex === -1) return null;

  const blocks =
    side === "left" ? [draggedItem.block, targetItem.block] : [targetItem.block, draggedItem.block];

  nextItems.splice(targetIndex, 1, {
    blocks,
    column_count: blocks.length,
    group_id: crypto.randomUUID(),
    type: "column_group",
  });

  return nextItems;
}

interface InsertPayload {
  draggedBlockId: number | string;
  groupId: string;
  side: string;
  targetBlockId: number | string;
}

function insertIntoColumnGroupItems(
  items: LayoutItem[],
  payload: InsertPayload,
): LayoutItem[] | null {
  const { draggedBlockId, groupId, side, targetBlockId } = payload;

  const draggedItem = items.find(
    (item) =>
      item.type === "full_width" && (item as FullWidthLayoutItem).block.id === draggedBlockId,
  ) as FullWidthLayoutItem | undefined;
  if (!draggedItem) return null;

  const nextItems = removeFullWidthItem(items, draggedBlockId);
  const groupIndex = nextItems.findIndex(
    (item) => item.type === "column_group" && (item as ColumnGroupLayoutItem).group_id === groupId,
  );

  if (groupIndex === -1) return null;

  const groupItem = nextItems[groupIndex] as ColumnGroupLayoutItem;
  if (groupItem.blocks.length >= 3) return null;

  const targetIndex = groupItem.blocks.findIndex((block) => block.id === targetBlockId);
  if (targetIndex === -1) return null;

  const nextBlocks = [...groupItem.blocks];
  const insertIndex = side === "left" ? targetIndex : targetIndex + 1;
  nextBlocks.splice(insertIndex, 0, draggedItem.block);

  nextItems.splice(groupIndex, 1, {
    ...groupItem,
    blocks: nextBlocks,
    column_count: nextBlocks.length,
  });

  return nextItems;
}

function dropSide(
  event: IDragEvent,
  hoveredElement: HTMLElement | undefined,
  threshold = 0.25,
): string | null {
  const pointer = event.provider?.pointer?.value?.current;
  if (!pointer || !hoveredElement) return null;

  const rect = hoveredElement.getBoundingClientRect();
  const relX = (pointer.x - rect.left) / rect.width;

  if (relX <= threshold) return "left";
  if (relX >= 1 - threshold) return "right";
  return null;
}

function handleInsertIntoColumnGroup(payload: InsertPayload): void {
  const nextItems = insertIntoColumnGroupItems(localItems.value, payload);
  if (!nextItems) return;

  localItems.value = nextItems;
  pushColumnLayout(nextItems);
}

function isColumnGroupBlock(item: LayoutItem | Block): item is Block {
  return "id" in item && !!item.id && item.type !== "full_width" && item.type !== "column_group";
}

function extractFromColumnGroup(
  items: LayoutItem[],
  block: Block,
  hoveredItem: LayoutItem | undefined,
  hoveredPlacement: { bottom?: boolean } | undefined,
): LayoutItem[] | null {
  const groupIndex = items.findIndex(
    (item) =>
      item.type === "column_group" &&
      (item as ColumnGroupLayoutItem).blocks.some((b) => b.id === block.id),
  );
  if (groupIndex === -1) return null;

  const group = items[groupIndex] as ColumnGroupLayoutItem;
  const nextItems = [...items];
  const remainingBlocks = group.blocks.filter((b) => b.id !== block.id);

  if (remainingBlocks.length <= 1) {
    const dissolved: FullWidthLayoutItem[] = remainingBlocks.map((b) => ({
      type: "full_width",
      block: b,
    }));
    nextItems.splice(groupIndex, 1, ...dissolved);
  } else {
    nextItems.splice(groupIndex, 1, {
      ...group,
      blocks: remainingBlocks,
      column_count: remainingBlocks.length,
    });
  }

  let insertIndex = nextItems.length;
  if (hoveredItem) {
    const hoveredIdx = nextItems.findIndex(
      (item) =>
        (item.type === "full_width" &&
          (item as FullWidthLayoutItem).block?.id ===
            (hoveredItem as FullWidthLayoutItem).block?.id) ||
        (item.type === "column_group" &&
          (item as ColumnGroupLayoutItem).group_id ===
            (hoveredItem as ColumnGroupLayoutItem).group_id),
    );
    if (hoveredIdx !== -1) {
      insertIndex = hoveredPlacement?.bottom ? hoveredIdx + 1 : hoveredIdx;
    }
  }

  nextItems.splice(insertIndex, 0, { type: "full_width", block });
  return nextItems;
}

// Flat list of blocks for vertical sortable
const containerRef = useTemplateRef("container");
makeDroppable(
  containerRef,
  {
    groups: ["blocks-vertical"],
    events: {
      onDrop: (e: IDragEvent) => {
        const draggedItem = e.draggedItems?.[0]?.item as LayoutItem | Block | undefined;
        const hoveredItem = e.hoveredDraggable?.item as LayoutItem | undefined;
        const side = dropSide(e, e.hoveredDraggable?.element);

        // Case 1: Create column group (full_width + full_width side drop)
        if (draggedItem?.type === "full_width" && hoveredItem?.type === "full_width" && side) {
          const nextItems = createColumnGroupItems(
            localItems.value,
            (draggedItem as FullWidthLayoutItem).block.id,
            (hoveredItem as FullWidthLayoutItem).block.id,
            side,
          );

          if (nextItems) {
            localItems.value = nextItems;
            pushColumnLayout(nextItems);
          }

          return;
        }

        // Case 2: Extract block from column group (dragged item is a Block from within a column group)
        if (draggedItem && isColumnGroupBlock(draggedItem)) {
          const nextItems = extractFromColumnGroup(
            localItems.value,
            draggedItem,
            hoveredItem,
            e.hoveredDraggable?.placement,
          );

          if (nextItems) {
            localItems.value = nextItems;
            pushColumnLayout(nextItems);
          }

          return;
        }

        // Case 3: Normal vertical reorder
        const result = e.helpers.suggestSort("vertical");
        if (!result) return;

        localItems.value = result.sourceItems as LayoutItem[];
        const ids = localItems.value.flatMap((item) =>
          item.type === "column_group"
            ? (item as ColumnGroupLayoutItem).blocks.map((b) => b.id)
            : [(item as FullWidthLayoutItem).block.id],
        );
        live.pushEvent("reorder_blocks", { ids });
      },
    },
  },
  () => localItems.value,
);

function resolveComponent(type: string): typeof TextBlock | null {
  return blockComponents[type] || null;
}
</script>

<template>
  <div ref="container" class="space-y-3">
    <DraggableBlock
      v-for="(item, index) in localItems"
      :key="
        item.type === 'full_width'
          ? (item as FullWidthLayoutItem).block.id
          : (item as ColumnGroupLayoutItem).group_id
      "
      :can-edit="canEdit"
      :index="index"
      :items="localItems"
    >
      <!-- Full-width block -->
      <template v-if="item.type === 'full_width'">
        <div class="relative">
          <component
            :is="resolveComponent((item as FullWidthLayoutItem).block.type)"
            :block="(item as FullWidthLayoutItem).block"
            :can-edit="canEdit && !isLockedByOther((item as FullWidthLayoutItem).block.id)"
          >
            <template #menu>
              <div class="flex items-center gap-0.5">
                <button
                  v-if="
                    (item as FullWidthLayoutItem).block.can_reattach &&
                    !isLockedByOther((item as FullWidthLayoutItem).block.id)
                  "
                  type="button"
                  class="size-6 rounded flex items-center justify-center text-blue-500 hover:bg-blue-500/10 transition-colors"
                  title="Reattach to parent"
                  @click.stop="reattachBlock((item as FullWidthLayoutItem).block.id)"
                >
                  <Link2 class="size-3.5" />
                </button>
                <UserAvatar
                  v-if="isLockedByOther((item as FullWidthLayoutItem).block.id)"
                  :email="lockInfo((item as FullWidthLayoutItem).block.id)?.userEmail"
                  :color="lockInfo((item as FullWidthLayoutItem).block.id)?.userColor"
                  size="xs"
                />
              </div>
            </template>
          </component>
          <div
            v-if="isLockedByOther((item as FullWidthLayoutItem).block.id)"
            class="absolute inset-0 rounded-lg border-2 pointer-events-none"
            :style="{ borderColor: lockInfo((item as FullWidthLayoutItem).block.id)?.userColor }"
          />
        </div>
      </template>

      <!-- Column group (horizontal sortable) -->
      <template v-else-if="item.type === 'column_group'">
        <SortableColumnGroup
          :group-id="(item as ColumnGroupLayoutItem).group_id"
          :blocks="(item as ColumnGroupLayoutItem).blocks"
          :column-count="(item as ColumnGroupLayoutItem).column_count"
          :can-edit="canEdit"
          @insert-full-width="handleInsertIntoColumnGroup"
        />
      </template>
    </DraggableBlock>
  </div>
</template>
