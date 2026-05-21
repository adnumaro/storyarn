import type { Block, ColumnGroupLayoutItem, FullWidthLayoutItem, LayoutItem } from "../../../types";

// ── Wire format ──────────────────────────────────────────────────────────────

export type LayoutWireEntry =
  | { kind: "full_width"; block_id: number | string }
  | { kind: "column_group"; group_id: string; block_ids: Array<number | string> };

export function serializeLayout(layout: LayoutItem[]): LayoutWireEntry[] {
  return layout.map((item) => {
    if (item.type === "full_width") {
      return { kind: "full_width", block_id: item.block.id };
    }
    return {
      kind: "column_group",
      group_id: item.group_id,
      block_ids: item.blocks.map((b) => b.id),
    };
  });
}

// ── Primitives ───────────────────────────────────────────────────────────────

function findFullWidth(
  layout: LayoutItem[],
  blockId: number | string,
): { item: FullWidthLayoutItem; index: number } | null {
  const index = layout.findIndex((it) => it.type === "full_width" && it.block.id === blockId);
  if (index === -1) return null;
  return { item: layout[index] as FullWidthLayoutItem, index };
}

function findGroup(
  layout: LayoutItem[],
  groupId: string,
): { item: ColumnGroupLayoutItem; index: number } | null {
  const index = layout.findIndex((it) => it.type === "column_group" && it.group_id === groupId);
  if (index === -1) return null;
  return { item: layout[index] as ColumnGroupLayoutItem, index };
}

function findBlockInGroups(
  layout: LayoutItem[],
  blockId: number | string,
): { groupItem: ColumnGroupLayoutItem; groupIndex: number; blockIndex: number } | null {
  for (let i = 0; i < layout.length; i++) {
    const it = layout[i];
    if (it.type !== "column_group") continue;
    const bi = it.blocks.findIndex((b) => b.id === blockId);
    if (bi !== -1) return { groupItem: it, groupIndex: i, blockIndex: bi };
  }
  return null;
}

function makeGroup(blocks: Block[], groupId?: string): ColumnGroupLayoutItem {
  return {
    type: "column_group",
    group_id: groupId ?? crypto.randomUUID(),
    blocks,
    column_count: blocks.length,
  };
}

/** If a group has <2 blocks, dissolve it into full_width items in place. */
function normalize(layout: LayoutItem[]): LayoutItem[] {
  const out: LayoutItem[] = [];
  for (const item of layout) {
    if (item.type === "column_group" && item.blocks.length < 2) {
      for (const b of item.blocks) {
        out.push({ type: "full_width", block: b });
      }
    } else if (item.type === "column_group") {
      out.push({ ...item, column_count: item.blocks.length });
    } else {
      out.push(item);
    }
  }
  return out;
}

/** Remove a block from wherever it lives in the layout. Returns [newLayout, removedBlock]. */
function extractBlock(
  layout: LayoutItem[],
  blockId: number | string,
): [LayoutItem[], Block | null] {
  const fw = findFullWidth(layout, blockId);
  if (fw) {
    const next = [...layout];
    next.splice(fw.index, 1);
    return [next, fw.item.block];
  }
  const found = findBlockInGroups(layout, blockId);
  if (!found) return [layout, null];
  const nextBlocks = [...found.groupItem.blocks];
  const [removed] = nextBlocks.splice(found.blockIndex, 1);
  const next = [...layout];
  next.splice(found.groupIndex, 1, { ...found.groupItem, blocks: nextBlocks });
  return [next, removed];
}

// ── Reducers (pure: (layout, args) => layout) ────────────────────────────────

export function createColumnGroup(
  layout: LayoutItem[],
  draggedBlockId: number | string,
  targetBlockId: number | string,
  side: "left" | "right",
  newGroupId?: string,
): LayoutItem[] {
  if (draggedBlockId === targetBlockId) return layout;
  const target = findFullWidth(layout, targetBlockId);
  if (!target) return layout;
  const [without, draggedBlock] = extractBlock(layout, draggedBlockId);
  if (!draggedBlock) return layout;

  const targetIdx = without.findIndex(
    (it) => it.type === "full_width" && it.block.id === targetBlockId,
  );
  if (targetIdx === -1) return layout;
  const targetItem = without[targetIdx] as FullWidthLayoutItem;

  const blocks =
    side === "left" ? [draggedBlock, targetItem.block] : [targetItem.block, draggedBlock];
  const next = [...without];
  next.splice(targetIdx, 1, makeGroup(blocks, newGroupId));
  return normalize(next);
}

export function insertIntoGroup(
  layout: LayoutItem[],
  draggedBlockId: number | string,
  groupId: string,
  targetBlockId: number | string,
  side: "left" | "right",
): LayoutItem[] {
  const group = findGroup(layout, groupId);
  if (!group) return layout;
  if (group.item.blocks.length >= 3) return layout;
  const targetIdx = group.item.blocks.findIndex((b) => b.id === targetBlockId);
  if (targetIdx === -1) return layout;

  const [without, draggedBlock] = extractBlock(layout, draggedBlockId);
  if (!draggedBlock) return layout;

  const afterRemovalGroup = findGroup(without, groupId);
  if (!afterRemovalGroup) return layout;
  const retargetIdx = afterRemovalGroup.item.blocks.findIndex((b) => b.id === targetBlockId);
  if (retargetIdx === -1) return layout;

  const nextBlocks = [...afterRemovalGroup.item.blocks];
  const insertAt = side === "left" ? retargetIdx : retargetIdx + 1;
  nextBlocks.splice(insertAt, 0, draggedBlock);
  if (nextBlocks.length > 3) return layout;

  const next = [...without];
  next.splice(afterRemovalGroup.index, 1, {
    ...afterRemovalGroup.item,
    blocks: nextBlocks,
    column_count: nextBlocks.length,
  });
  return normalize(next);
}

export function extractFromGroup(
  layout: LayoutItem[],
  draggedBlockId: number | string,
  hoverBlockId: number | string | null,
  side: "before" | "after",
): LayoutItem[] {
  const found = findBlockInGroups(layout, draggedBlockId);
  if (!found) return layout;
  const [without, draggedBlock] = extractBlock(layout, draggedBlockId);
  if (!draggedBlock) return layout;

  let insertIndex = without.length;
  if (hoverBlockId != null) {
    const hoveredFw = without.findIndex(
      (it) => it.type === "full_width" && it.block.id === hoverBlockId,
    );
    if (hoveredFw !== -1) {
      insertIndex = side === "after" ? hoveredFw + 1 : hoveredFw;
    } else {
      const hoveredInGroup = without.findIndex(
        (it) => it.type === "column_group" && it.blocks.some((b) => b.id === hoverBlockId),
      );
      if (hoveredInGroup !== -1) {
        insertIndex = side === "after" ? hoveredInGroup + 1 : hoveredInGroup;
      }
    }
  }
  const next = [...without];
  next.splice(insertIndex, 0, { type: "full_width", block: draggedBlock });
  return normalize(next);
}

export function reorderWithinGroup(
  layout: LayoutItem[],
  groupId: string,
  draggedBlockId: number | string,
  targetBlockId: number | string,
  side: "before" | "after",
): LayoutItem[] {
  if (draggedBlockId === targetBlockId) return layout;
  const group = findGroup(layout, groupId);
  if (!group) return layout;
  const fromIdx = group.item.blocks.findIndex((b) => b.id === draggedBlockId);
  const toIdx = group.item.blocks.findIndex((b) => b.id === targetBlockId);
  if (fromIdx === -1 || toIdx === -1) return layout;

  const nextBlocks = [...group.item.blocks];
  const [moved] = nextBlocks.splice(fromIdx, 1);
  const targetAfterRemoval = nextBlocks.findIndex((b) => b.id === targetBlockId);
  if (targetAfterRemoval === -1) return layout;
  const insertAt = side === "before" ? targetAfterRemoval : targetAfterRemoval + 1;
  nextBlocks.splice(insertAt, 0, moved);

  const next = [...layout];
  next.splice(group.index, 1, { ...group.item, blocks: nextBlocks });
  return normalize(next);
}

export function transferBetweenGroups(
  layout: LayoutItem[],
  draggedBlockId: number | string,
  targetGroupId: string,
  targetBlockId: number | string,
  side: "left" | "right",
): LayoutItem[] {
  const target = findGroup(layout, targetGroupId);
  if (!target) return layout;
  if (target.item.blocks.length >= 3) return layout;

  const [without, draggedBlock] = extractBlock(layout, draggedBlockId);
  if (!draggedBlock) return layout;

  const afterRemoval = findGroup(without, targetGroupId);
  if (!afterRemoval) return layout;
  const retargetIdx = afterRemoval.item.blocks.findIndex((b) => b.id === targetBlockId);
  if (retargetIdx === -1) return layout;
  const nextBlocks = [...afterRemoval.item.blocks];
  const insertAt = side === "left" ? retargetIdx : retargetIdx + 1;
  nextBlocks.splice(insertAt, 0, draggedBlock);
  if (nextBlocks.length > 3) return layout;

  const next = [...without];
  next.splice(afterRemoval.index, 1, {
    ...afterRemoval.item,
    blocks: nextBlocks,
    column_count: nextBlocks.length,
  });
  return normalize(next);
}

export function verticalReorder(
  layout: LayoutItem[],
  draggedKey: { kind: "full_width"; blockId: number | string } | { kind: "group"; groupId: string },
  hoverKey: { kind: "full_width"; blockId: number | string } | { kind: "group"; groupId: string },
  side: "before" | "after",
): LayoutItem[] {
  const fromIdx =
    draggedKey.kind === "full_width"
      ? layout.findIndex((it) => it.type === "full_width" && it.block.id === draggedKey.blockId)
      : layout.findIndex((it) => it.type === "column_group" && it.group_id === draggedKey.groupId);
  const toIdx =
    hoverKey.kind === "full_width"
      ? layout.findIndex((it) => it.type === "full_width" && it.block.id === hoverKey.blockId)
      : layout.findIndex((it) => it.type === "column_group" && it.group_id === hoverKey.groupId);
  if (fromIdx === -1 || toIdx === -1 || fromIdx === toIdx) return layout;

  const next = [...layout];
  const [moved] = next.splice(fromIdx, 1);
  const targetAfterRemoval = next.findIndex((it) =>
    hoverKey.kind === "full_width"
      ? it.type === "full_width" && it.block.id === hoverKey.blockId
      : it.type === "column_group" && it.group_id === hoverKey.groupId,
  );
  if (targetAfterRemoval === -1) return layout;
  const insertAt = side === "before" ? targetAfterRemoval : targetAfterRemoval + 1;
  next.splice(insertAt, 0, moved);
  return normalize(next);
}

export function appendAsFullWidth(
  layout: LayoutItem[],
  draggedBlockId: number | string,
): LayoutItem[] {
  const [without, draggedBlock] = extractBlock(layout, draggedBlockId);
  if (!draggedBlock) return layout;
  return normalize([...without, { type: "full_width", block: draggedBlock }]);
}
