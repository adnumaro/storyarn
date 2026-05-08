<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import type { IDragEvent } from "@vue-dnd-kit/core";
import { Link2 } from "lucide-vue-next";
import { inject, ref, useTemplateRef, watch } from "vue";
import UserAvatar from "@components/UserAvatar.vue";
import { useLive } from "../../../../shared/composables/useLive";
import type {
  BlockLock,
  ColumnGroupLayoutItem,
  FullWidthLayoutItem,
  LayoutItem,
} from "../../types";
import BooleanBlock from "../blocks/BooleanBlock.vue";
import DateBlock from "../blocks/DateBlock.vue";
import GalleryBlock from "../blocks/galleryBlock/GalleryBlock.vue";
import MultiSelectBlock from "../blocks/MultiSelectBlock.vue";
import NumberBlock from "../blocks/NumberBlock.vue";
import ReferenceBlock from "../blocks/ReferenceBlock.vue";
import RichTextBlock from "../blocks/richText/RichTextBlock.vue";
import SelectBlock from "../blocks/SelectBlock.vue";
import TableBlock from "../blocks/table/TableBlock.vue";
import TextBlock from "../blocks/TextBlock.vue";
import BlockDndItem, { type DndItemData } from "./BlockDndItem.vue";
import {
  appendAsFullWidth,
  createColumnGroup,
  extractFromGroup,
  insertIntoGroup,
  reorderWithinGroup,
  serializeLayout,
  transferBetweenGroups,
  verticalReorder,
} from "./layout-reducers";

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
  layoutItems?: LayoutItem[];
  canEdit?: boolean;
}>();

const isLockedByOther = inject<(id: number | string) => boolean>("isLockedByOther", () => false);
const lockInfo = inject<(id: number | string) => BlockLock | null>("lockInfo", () => null);

const live = useLive();

const localItems = ref<LayoutItem[]>([...layoutItems]);
watch(
  () => layoutItems,
  (v) => {
    localItems.value = [...v];
  },
);

function pushLayout(items: LayoutItem[]): void {
  localItems.value = items;
  live.pushEvent("reorder_layout", { layout: serializeLayout(items) });
}

function reattachBlock(id: number | string): void {
  live.pushEvent("reattach_block", { id });
}

function resolveComponent(type: string): typeof TextBlock | null {
  return blockComponents[type] || null;
}

function gridClass(n: number): string {
  if (n === 2) return "sm:grid-cols-2";
  if (n === 3) return "sm:grid-cols-3";
  return "sm:grid-cols-1";
}

// ── Drop routing ─────────────────────────────────────────────────────────────

const SIDE_THRESHOLD = 0.25;

type DropSide = "left" | "right" | "top" | "bottom";

function computeSide(
  element: HTMLElement | undefined,
  pointer: { x: number; y: number } | undefined,
): DropSide | null {
  if (!element || !pointer) return null;
  const rect = element.getBoundingClientRect();
  const relX = (pointer.x - rect.left) / rect.width;
  if (relX <= SIDE_THRESHOLD) return "left";
  if (relX >= 1 - SIDE_THRESHOLD) return "right";
  const relY = (pointer.y - rect.top) / rect.height;
  return relY < 0.5 ? "top" : "bottom";
}

function extractDropContext(e: IDragEvent): {
  dragged: DndItemData | undefined;
  hovered: DndItemData | undefined;
  side: DropSide | null;
} {
  const hoveredCtx = e.hoveredDraggable;
  return {
    dragged: e.draggedItems?.[0]?.data as DndItemData | undefined,
    hovered: hoveredCtx?.data as DndItemData | undefined,
    side: computeSide(hoveredCtx?.element, e.provider?.pointer?.value?.current),
  };
}

type HorizontalSide = "left" | "right";
type VerticalSide = "before" | "after";

function toHorizontalSide(side: DropSide | null): HorizontalSide | null {
  if (side === "left" || side === "right") return side;
  return null;
}

function toVerticalSide(side: DropSide | null): VerticalSide | null {
  if (side === "top") return "before";
  if (side === "bottom") return "after";
  return null;
}

type ReorderKey =
  | { kind: "full_width"; blockId: number | string }
  | { kind: "group"; groupId: string };

function toReorderKey(d: DndItemData): ReorderKey | null {
  if (d.kind === "full_width" && d.blockId != null) {
    return { kind: "full_width", blockId: d.blockId };
  }
  if (d.kind === "group" && d.groupId) {
    return { kind: "group", groupId: d.groupId };
  }
  return null;
}

function isFw(d: DndItemData): d is DndItemData & { kind: "full_width"; blockId: number | string } {
  return d.kind === "full_width" && d.blockId != null;
}

function isChild(
  d: DndItemData,
): d is DndItemData & { kind: "column_child"; blockId: number | string; groupId: string } {
  return d.kind === "column_child" && d.blockId != null && !!d.groupId;
}

type FwData = DndItemData & { kind: "full_width"; blockId: number | string };
type ChildData = DndItemData & {
  kind: "column_child";
  blockId: number | string;
  groupId: string;
};

function childToChild(dragged: ChildData, hovered: ChildData, side: HorizontalSide): LayoutItem[] {
  if (dragged.groupId === hovered.groupId) {
    return reorderWithinGroup(
      localItems.value,
      dragged.groupId,
      dragged.blockId,
      hovered.blockId,
      side === "left" ? "before" : "after",
    );
  }
  return transferBetweenGroups(
    localItems.value,
    dragged.blockId,
    hovered.groupId,
    hovered.blockId,
    side,
  );
}

function fwToAny(dragged: FwData, hovered: DndItemData, side: HorizontalSide): LayoutItem[] | null {
  if (isFw(hovered)) {
    return createColumnGroup(localItems.value, dragged.blockId, hovered.blockId, side);
  }
  if (isChild(hovered)) {
    return insertIntoGroup(
      localItems.value,
      dragged.blockId,
      hovered.groupId,
      hovered.blockId,
      side,
    );
  }
  return null;
}

function tryHorizontal(
  dragged: DndItemData,
  hovered: DndItemData,
  side: HorizontalSide,
): LayoutItem[] | null {
  if (isFw(dragged)) return fwToAny(dragged, hovered, side);
  if (isChild(dragged) && isChild(hovered)) return childToChild(dragged, hovered, side);
  return null;
}

function tryVertical(
  dragged: DndItemData,
  hovered: DndItemData,
  side: VerticalSide,
): LayoutItem[] | null {
  // column_child → top/bottom of anything = extract
  if (dragged.kind === "column_child" && dragged.blockId != null) {
    const hoverId = hovered.kind === "group" ? null : (hovered.blockId ?? null);
    return extractFromGroup(localItems.value, dragged.blockId, hoverId, side);
  }
  // full_width / group → top/bottom of full_width / group = vertical reorder
  const draggedKey = toReorderKey(dragged);
  const hoverKey = toReorderKey(hovered);
  if (draggedKey && hoverKey) {
    return verticalReorder(localItems.value, draggedKey, hoverKey, side);
  }
  return null;
}

function onDrop(e: IDragEvent): void {
  const { dragged, hovered, side } = extractDropContext(e);
  if (!dragged) return;

  if (!hovered || !side) {
    if (dragged.kind === "full_width" && dragged.blockId != null) {
      pushLayout(appendAsFullWidth(localItems.value, dragged.blockId));
    }
    return;
  }

  const hSide = toHorizontalSide(side);
  if (hSide) {
    const result = tryHorizontal(dragged, hovered, hSide);
    if (result) pushLayout(result);
    return;
  }

  const vSide = toVerticalSide(side);
  if (vSide) {
    const result = tryVertical(dragged, hovered, vSide);
    if (result) pushLayout(result);
  }
}

const containerRef = useTemplateRef("container");
makeDroppable(
  containerRef,
  {
    groups: ["sheet-blocks"],
    events: { onDrop },
  },
  () => localItems.value,
);
</script>

<template>
  <div ref="container" class="space-y-3">
    <template
      v-for="item in localItems"
      :key="
        item.type === 'full_width'
          ? `fw-${(item as FullWidthLayoutItem).block.id}`
          : `cg-${(item as ColumnGroupLayoutItem).group_id}`
      "
    >
      <!-- Full-width block -->
      <BlockDndItem
        v-if="item.type === 'full_width'"
        kind="full_width"
        :block-id="(item as FullWidthLayoutItem).block.id"
        :can-edit="canEdit"
      >
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
                  :title="$t('sheets.dnd.reattach')"
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
      </BlockDndItem>

      <!-- Column group: draggable as a whole (via wrapper) + each child draggable -->
      <BlockDndItem
        v-else-if="item.type === 'column_group'"
        kind="group"
        :group-id="(item as ColumnGroupLayoutItem).group_id"
        :can-edit="canEdit"
        indicator-axis="vertical"
      >
        <div :class="['grid gap-6', gridClass((item as ColumnGroupLayoutItem).column_count)]">
          <BlockDndItem
            v-for="block in (item as ColumnGroupLayoutItem).blocks"
            :key="block.id"
            kind="column_child"
            :block-id="block.id"
            :group-id="(item as ColumnGroupLayoutItem).group_id"
            :can-edit="canEdit"
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
          </BlockDndItem>
        </div>
      </BlockDndItem>
    </template>
  </div>
</template>
