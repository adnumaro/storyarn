import { describe, expect, it } from "vitest";
import {
  appendAsFullWidth,
  createColumnGroup,
  extractFromGroup,
  insertIntoGroup,
  reorderWithinGroup,
  serializeLayout,
  transferBetweenGroups,
  verticalReorder,
} from "@modules/sheets/components/dnd/layout-reducers";
import type { Block, ColumnGroupLayoutItem, LayoutItem } from "@modules/sheets/types";

function fw(id: number): LayoutItem {
  return { type: "full_width", block: { id, type: "text" } as Block };
}

function cg(groupId: string, ids: number[]): LayoutItem {
  return {
    type: "column_group",
    group_id: groupId,
    blocks: ids.map((id) => ({ id, type: "text" }) as Block),
    column_count: ids.length,
  };
}

function ids(layout: LayoutItem[]): Array<string | number[]> {
  return layout.map((it) => {
    if (it.type === "full_width") return it.block.id as number;
    return (it as ColumnGroupLayoutItem).blocks.map((b) => b.id as number);
  }) as Array<string | number[]>;
}

describe("createColumnGroup", () => {
  it("creates a group from two full-width blocks (side=right)", () => {
    const layout = [fw(1), fw(2), fw(3)];
    const result = createColumnGroup(layout, 1, 2, "right", "g1");
    // block 1 removed, target becomes group [2, 1]
    expect(ids(result)).toEqual([[2, 1], 3]);
  });

  it("creates a group with side=left", () => {
    const layout = [fw(1), fw(2)];
    const result = createColumnGroup(layout, 2, 1, "left", "g1");
    expect(ids(result)).toEqual([[2, 1]]);
  });

  it("is a no-op when dragging onto itself", () => {
    const layout = [fw(1), fw(2)];
    const result = createColumnGroup(layout, 1, 1, "right");
    expect(result).toBe(layout);
  });

  it("is a no-op when target does not exist", () => {
    const layout = [fw(1)];
    const result = createColumnGroup(layout, 1, 99, "right");
    expect(result).toBe(layout);
  });
});

describe("insertIntoGroup", () => {
  it("inserts full-width into existing group", () => {
    const layout: LayoutItem[] = [fw(1), cg("g1", [2, 3])];
    const result = insertIntoGroup(layout, 1, "g1", 2, "left");
    expect(ids(result)).toEqual([[1, 2, 3]]);
  });

  it("inserts on the right of target", () => {
    const layout: LayoutItem[] = [cg("g1", [2, 3]), fw(1)];
    const result = insertIntoGroup(layout, 1, "g1", 3, "right");
    expect(ids(result)).toEqual([[2, 3, 1]]);
  });

  it("rejects when group already has 3", () => {
    const layout: LayoutItem[] = [cg("g1", [2, 3, 4]), fw(1)];
    const result = insertIntoGroup(layout, 1, "g1", 2, "left");
    expect(result).toBe(layout);
  });
});

describe("extractFromGroup", () => {
  it("extracts block into full_width at top of list when no hover", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2, 3])];
    const result = extractFromGroup(layout, 2, null, "after");
    // no hover ⇒ appended at end
    expect(ids(result)).toEqual([[1, 3], 2]);
  });

  it("dissolves group when only one block remains", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2])];
    const result = extractFromGroup(layout, 2, null, "after");
    expect(ids(result)).toEqual([1, 2]);
  });

  it("places extracted block before a hovered full_width", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2, 3]), fw(9)];
    const result = extractFromGroup(layout, 2, 9, "before");
    expect(ids(result)).toEqual([[1, 3], 2, 9]);
  });

  it("places extracted block after a hovered full_width", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2, 3]), fw(9)];
    const result = extractFromGroup(layout, 2, 9, "after");
    expect(ids(result)).toEqual([[1, 3], 9, 2]);
  });
});

describe("reorderWithinGroup", () => {
  it("moves a block to the right of another within the same group", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2, 3])];
    const result = reorderWithinGroup(layout, "g1", 1, 3, "after");
    expect(ids(result)).toEqual([[2, 3, 1]]);
  });

  it("moves a block to the left of another", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2, 3])];
    const result = reorderWithinGroup(layout, "g1", 3, 1, "before");
    expect(ids(result)).toEqual([[3, 1, 2]]);
  });

  it("no-op when dragging onto itself", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2])];
    expect(reorderWithinGroup(layout, "g1", 1, 1, "after")).toBe(layout);
  });
});

describe("transferBetweenGroups", () => {
  it("moves a block from one group to another", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2]), cg("g2", [3, 4])];
    const result = transferBetweenGroups(layout, 1, "g2", 3, "left");
    // g1 had [1,2] → [2]; dissolved into fw(2). g2 becomes [1,3,4].
    expect(ids(result)).toEqual([2, [1, 3, 4]]);
  });

  it("rejects when target group is already full", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2]), cg("g2", [3, 4, 5])];
    const result = transferBetweenGroups(layout, 1, "g2", 3, "left");
    expect(result).toBe(layout);
  });
});

describe("verticalReorder", () => {
  it("reorders full_width below another full_width", () => {
    const layout = [fw(1), fw(2), fw(3)];
    const result = verticalReorder(
      layout,
      { kind: "full_width", blockId: 1 },
      { kind: "full_width", blockId: 3 },
      "after",
    );
    expect(ids(result)).toEqual([2, 3, 1]);
  });

  it("reorders a whole column_group", () => {
    const layout: LayoutItem[] = [fw(1), cg("g1", [2, 3]), fw(4)];
    const result = verticalReorder(
      layout,
      { kind: "group", groupId: "g1" },
      { kind: "full_width", blockId: 4 },
      "after",
    );
    expect(ids(result)).toEqual([1, 4, [2, 3]]);
  });
});

describe("appendAsFullWidth", () => {
  it("appends a dragged full_width at the end", () => {
    const layout = [fw(1), fw(2)];
    const result = appendAsFullWidth(layout, 1);
    expect(ids(result)).toEqual([2, 1]);
  });

  it("extracts from group and appends, dissolving if needed", () => {
    const layout: LayoutItem[] = [cg("g1", [1, 2])];
    const result = appendAsFullWidth(layout, 1);
    expect(ids(result)).toEqual([2, 1]);
  });
});

describe("serializeLayout", () => {
  it("round-trips a mixed layout", () => {
    const layout: LayoutItem[] = [fw(1), cg("g1", [2, 3]), fw(4)];
    expect(serializeLayout(layout)).toEqual([
      { kind: "full_width", block_id: 1 },
      { kind: "column_group", group_id: "g1", block_ids: [2, 3] },
      { kind: "full_width", block_id: 4 },
    ]);
  });
});
