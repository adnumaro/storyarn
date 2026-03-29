<script setup>
import { makeDroppable } from "@vue-dnd-kit/core";
import { inject, ref, useTemplateRef, watch } from "vue";
import { useLive } from "@/vue/composables/useLive.js";

const isLockedByOther = inject("isLockedByOther", () => false);
const lockInfo = inject("lockInfo", () => null);

import UserAvatar from "@/vue/components/layout/UserAvatar.vue";
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
	groupId: { type: String, required: true },
	blocks: { type: Array, required: true },
	columnCount: { type: Number, default: 2 },
	canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(["insert-full-width"]);

const live = useLive();

const localBlocks = ref([...props.blocks]);
watch(
	() => props.blocks,
	(v) => {
		localBlocks.value = [...v];
	},
);

const gridRef = useTemplateRef("gridRef");
const columnGroup = `column-${props.groupId}`;

makeDroppable(
	gridRef,
	{
		groups: [columnGroup],
		events: {
			onDrop: (e) => {
				const result = e.helpers.suggestSort("horizontal");
				if (!result) return;
				localBlocks.value = result.sourceItems;
				// Push reorder with column indices
				const items = localBlocks.value.map((b, i) => ({
					id: b.id,
					column_group_id: props.groupId,
					column_index: i,
				}));
				live.pushEvent("reorder_column_group", {
					group_id: props.groupId,
					items,
				});
			},
		},
	},
	() => localBlocks.value,
);

function resolveComponent(type) {
	return blockComponents[type] || null;
}

function gridClass() {
	if (props.columnCount === 2) return "sm:grid-cols-2";
	if (props.columnCount === 3) return "sm:grid-cols-3";
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
        <div v-if="isLockedByOther(block.id)" class="absolute inset-0 rounded-lg border-2 pointer-events-none" :style="{ borderColor: lockInfo(block.id)?.userColor }" />
      </div>
    </HorizontalDraggableItem>
  </div>
</template>
