<script setup>
import { ref, useTemplateRef, watch } from "vue";
import { useLive } from "@/vue/composables/useLive";
import { makeDroppable } from "@vue-dnd-kit/core";
import DraggableBlock from "./DraggableBlock.vue";
import SortableColumnGroup from "./SortableColumnGroup.vue";

// Block type components
import TextBlock from "./blocks/TextBlock.vue";
import NumberBlock from "./blocks/NumberBlock.vue";
import BooleanBlock from "./blocks/BooleanBlock.vue";
import SelectBlock from "./blocks/SelectBlock.vue";
import MultiSelectBlock from "./blocks/MultiSelectBlock.vue";
import DateBlock from "./blocks/DateBlock.vue";
import RichTextBlock from "./blocks/RichTextBlock.vue";
import GalleryBlock from "./blocks/GalleryBlock.vue";
import TableBlock from "./blocks/TableBlock.vue";

const blockComponents = {
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

const props = defineProps({
	/** Layout items: [{type:"full_width", block:{...}}, {type:"column_group", group_id, blocks:[...], column_count}] */
	layoutItems: { type: Array, default: () => [] },
	canEdit: { type: Boolean, default: false },
});

const live = useLive();

const localItems = ref([...props.layoutItems]);
watch(
	() => props.layoutItems,
	(v) => {
		localItems.value = [...v];
	},
);

function serializeLayout(items) {
	return items.flatMap((item) =>
		item.type === "column_group"
			? item.blocks.map((block, index) => ({
					column_group_id: item.group_id,
					column_index: index,
					id: block.id,
				}))
			: [
					{
						column_group_id: null,
						column_index: 0,
						id: item.block.id,
					},
				],
	);
}

function pushColumnLayout(items) {
	live.pushEvent("reorder_with_columns", { items: serializeLayout(items) });
}

function removeFullWidthItem(items, blockId) {
	return items.filter(
		(item) => !(item.type === "full_width" && item.block.id === blockId),
	);
}

function createColumnGroupItems(items, draggedBlockId, targetBlockId, side) {
	if (draggedBlockId === targetBlockId) return null;

	const draggedItem = items.find(
		(item) => item.type === "full_width" && item.block.id === draggedBlockId,
	);
	const targetItem = items.find(
		(item) => item.type === "full_width" && item.block.id === targetBlockId,
	);

	if (!draggedItem || !targetItem) return null;

	const nextItems = removeFullWidthItem(items, draggedBlockId);
	const targetIndex = nextItems.findIndex(
		(item) => item.type === "full_width" && item.block.id === targetBlockId,
	);

	if (targetIndex === -1) return null;

	const blocks =
		side === "left"
			? [draggedItem.block, targetItem.block]
			: [targetItem.block, draggedItem.block];

	nextItems.splice(targetIndex, 1, {
		blocks,
		column_count: blocks.length,
		group_id: crypto.randomUUID(),
		type: "column_group",
	});

	return nextItems;
}

function insertIntoColumnGroupItems(items, payload) {
	const { draggedBlockId, groupId, side, targetBlockId } = payload;

	const draggedItem = items.find(
		(item) => item.type === "full_width" && item.block.id === draggedBlockId,
	);
	if (!draggedItem) return null;

	const nextItems = removeFullWidthItem(items, draggedBlockId);
	const groupIndex = nextItems.findIndex(
		(item) => item.type === "column_group" && item.group_id === groupId,
	);

	if (groupIndex === -1) return null;

	const groupItem = nextItems[groupIndex];
	if (groupItem.blocks.length >= 3) return null;

	const targetIndex = groupItem.blocks.findIndex(
		(block) => block.id === targetBlockId,
	);
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

function dropSide(event, hoveredElement, threshold = 0.25) {
	const pointer = event.provider?.pointer?.value?.current;
	if (!pointer || !hoveredElement) return null;

	const rect = hoveredElement.getBoundingClientRect();
	const relX = (pointer.x - rect.left) / rect.width;

	if (relX <= threshold) return "left";
	if (relX >= 1 - threshold) return "right";
	return null;
}

function handleInsertIntoColumnGroup(payload) {
	const nextItems = insertIntoColumnGroupItems(localItems.value, payload);
	if (!nextItems) return;

	localItems.value = nextItems;
	pushColumnLayout(nextItems);
}

function isColumnGroupBlock(item) {
	return (
		item &&
		item.id &&
		item.type !== "full_width" &&
		item.type !== "column_group"
	);
}

function extractFromColumnGroup(items, block, hoveredItem, hoveredPlacement) {
	const groupIndex = items.findIndex(
		(item) =>
			item.type === "column_group" &&
			item.blocks.some((b) => b.id === block.id),
	);
	if (groupIndex === -1) return null;

	const group = items[groupIndex];
	const nextItems = [...items];
	const remainingBlocks = group.blocks.filter((b) => b.id !== block.id);

	if (remainingBlocks.length <= 1) {
		const dissolved = remainingBlocks.map((b) => ({
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
					item.block?.id === hoveredItem.block?.id) ||
				(item.type === "column_group" &&
					item.group_id === hoveredItem.group_id),
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
			onDrop: (e) => {
				const draggedItem = e.draggedItems?.[0]?.item;
				const hoveredItem = e.hoveredDraggable?.item;
				const side = dropSide(e, e.hoveredDraggable?.element);

				// Case 1: Create column group (full_width + full_width side drop)
				if (
					draggedItem?.type === "full_width" &&
					hoveredItem?.type === "full_width" &&
					side
				) {
					const nextItems = createColumnGroupItems(
						localItems.value,
						draggedItem.block.id,
						hoveredItem.block.id,
						side,
					);

					if (nextItems) {
						localItems.value = nextItems;
						pushColumnLayout(nextItems);
					}

					return;
				}

				// Case 2: Extract block from column group
				if (isColumnGroupBlock(draggedItem)) {
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

				localItems.value = result.sourceItems;
				const ids = localItems.value.flatMap((item) =>
					item.type === "column_group"
						? item.blocks.map((b) => b.id)
						: [item.block.id],
				);
				live.pushEvent("reorder_blocks", { ids });
			},
		},
	},
	() => localItems.value,
);

function resolveComponent(type) {
	return blockComponents[type] || null;
}
</script>

<template>
  <div ref="container" class="space-y-3">
    <DraggableBlock
      v-for="(item, index) in localItems"
      :key="item.type === 'full_width' ? item.block.id : item.group_id"
      :can-edit="canEdit"
      :index="index"
      :items="localItems"
    >
      <!-- Full-width block -->
      <template v-if="item.type === 'full_width'">
        <component
          :is="resolveComponent(item.block.type)"
          :block="item.block"
          :can-edit="canEdit"
        />
      </template>

      <!-- Column group (horizontal sortable) -->
      <template v-else-if="item.type === 'column_group'">
        <SortableColumnGroup
          :group-id="item.group_id"
          :blocks="item.blocks"
          :column-count="item.column_count"
          :can-edit="canEdit"
          @insert-full-width="handleInsertIntoColumnGroup"
        />
      </template>
    </DraggableBlock>
  </div>
</template>
