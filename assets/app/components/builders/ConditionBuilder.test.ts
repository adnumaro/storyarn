import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import ConditionBuilder from "./ConditionBuilder.vue";
import type { ConditionData, ConditionBlock, ConditionGroup } from "./types";

function makeBlock(overrides: Partial<ConditionBlock> = {}): ConditionBlock {
  return {
    id: overrides.id ?? "b1",
    type: "block",
    logic: "all",
    rules: [{ id: "r1", sheet: "mc", variable: "health", operator: "equals", value: "10" }],
    ...overrides,
  };
}

function makeGroup(blocks: ConditionBlock[], id = "g1"): ConditionGroup {
  return { id, type: "group", logic: "all", blocks };
}

function mountBuilder(condition: ConditionData | null = null, extra: Record<string, unknown> = {}) {
  return mount(ConditionBuilder, {
    props: { condition, ...extra },
    shallow: true,
  });
}

function lastEmitted(wrapper: ReturnType<typeof mount>): ConditionData {
  const events = wrapper.emitted("update:condition") as ConditionData[][];
  return events[events.length - 1][0];
}

describe("ConditionBuilder", () => {
  describe("ensureBlockFormat", () => {
    it("returns empty blocks for null condition", () => {
      const w = mountBuilder(null);
      const addBtn = w.find("button");
      expect(addBtn.exists()).toBe(true);
    });

    it("preserves condition that already has blocks", () => {
      const condition: ConditionData = {
        logic: "any",
        blocks: [makeBlock()],
      };
      const w = mountBuilder(condition);
      w.findAll("button").find((b) => b.text().includes("Add block"))?.trigger("click");
      const emitted = lastEmitted(w);
      expect(emitted.logic).toBe("any");
      expect(emitted.blocks.length).toBe(2);
      expect(emitted.blocks[0]).toMatchObject({ id: "b1", type: "block" });
    });
  });

  describe("addBlock", () => {
    it("adds a new block with default rule", async () => {
      const w = mountBuilder({ logic: "all", blocks: [] });
      await w.findAll("button").find((b) => b.text().includes("Add block"))!.trigger("click");
      const emitted = lastEmitted(w);
      expect(emitted.blocks).toHaveLength(1);
      const block = emitted.blocks[0] as ConditionBlock;
      expect(block.type).toBe("block");
      expect(block.rules).toHaveLength(1);
      expect(block.rules[0].operator).toBe("equals");
      expect(block.id).toMatch(/^block_/);
    });

    it("adds label field in switchMode", async () => {
      const w = mountBuilder({ logic: "all", blocks: [] }, { switchMode: true });
      await w.findAll("button").find((b) => b.text().includes("Add block"))!.trigger("click");
      const emitted = lastEmitted(w);
      const block = emitted.blocks[0] as ConditionBlock;
      expect(block).toHaveProperty("label", "");
    });

    it("appends to existing blocks", async () => {
      const w = mountBuilder({ logic: "all", blocks: [makeBlock()] });
      await w.findAll("button").find((b) => b.text().includes("Add block"))!.trigger("click");
      const emitted = lastEmitted(w);
      expect(emitted.blocks).toHaveLength(2);
      expect(emitted.blocks[0].id).toBe("b1");
    });
  });

  describe("removeBlock", () => {
    it("emits update without the removed block", () => {
      const b1 = makeBlock({ id: "b1" });
      const b2 = makeBlock({ id: "b2" });
      const w = mountBuilder({ logic: "all", blocks: [b1, b2] });

      // ConditionBlock stub emits "remove"
      const blockStubs = w.findAllComponents({ name: "ConditionBlock" });
      blockStubs[0].vm.$emit("remove");

      const emitted = lastEmitted(w);
      expect(emitted.blocks).toHaveLength(1);
      expect(emitted.blocks[0].id).toBe("b2");
    });
  });

  describe("updateBlock", () => {
    it("replaces the block at the given index", () => {
      const b1 = makeBlock({ id: "b1" });
      const b2 = makeBlock({ id: "b2" });
      const w = mountBuilder({ logic: "all", blocks: [b1, b2] });

      const updated = { ...b1, logic: "any" as const };
      const blockStubs = w.findAllComponents({ name: "ConditionBlock" });
      blockStubs[0].vm.$emit("update:block", updated);

      const emitted = lastEmitted(w);
      expect((emitted.blocks[0] as ConditionBlock).logic).toBe("any");
      expect(emitted.blocks[1].id).toBe("b2");
    });
  });

  describe("ungroupGroup", () => {
    it("replaces group with its inner blocks", () => {
      const inner1 = makeBlock({ id: "inner1" });
      const inner2 = makeBlock({ id: "inner2" });
      const group = makeGroup([inner1, inner2], "g1");
      const standalone = makeBlock({ id: "standalone" });

      const w = mountBuilder({ logic: "all", blocks: [group, standalone] });

      const groupStub = w.findComponent({ name: "ConditionGroup" });
      groupStub.vm.$emit("ungroup");

      const emitted = lastEmitted(w);
      expect(emitted.blocks).toHaveLength(3);
      expect(emitted.blocks[0].id).toBe("inner1");
      expect(emitted.blocks[1].id).toBe("inner2");
      expect(emitted.blocks[2].id).toBe("standalone");
    });
  });

  describe("selection mode & grouping", () => {
    it("enters and cancels selection mode", async () => {
      const b1 = makeBlock({ id: "b1" });
      const b2 = makeBlock({ id: "b2" });
      const w = mountBuilder({ logic: "all", blocks: [b1, b2] });

      // Group button visible when 2+ standalone blocks
      const groupBtn = w.findAll("button").find((b) => b.text().includes("Group"));
      expect(groupBtn?.exists()).toBe(true);

      await groupBtn!.trigger("click");
      // Now in selection mode — Cancel button should appear
      expect(w.findAll("button").some((b) => b.text().includes("Cancel"))).toBe(true);

      // Cancel
      await w.findAll("button").find((b) => b.text().includes("Cancel"))!.trigger("click");
      // Back to normal — Group button visible again
      expect(w.findAll("button").some((b) => b.text().includes("Group"))).toBe(true);
    });

    it("groups selected blocks into a group", async () => {
      const b1 = makeBlock({ id: "b1" });
      const b2 = makeBlock({ id: "b2" });
      const b3 = makeBlock({ id: "b3" });
      const w = mountBuilder({ logic: "all", blocks: [b1, b2, b3] });

      // Enter selection mode
      await w.findAll("button").find((b) => b.text().includes("Group"))!.trigger("click");

      // Select b1 and b3 via checkboxes
      const checkboxes = w.findAll("input[type='checkbox']");
      await checkboxes[0].setValue(true);
      await checkboxes[2].setValue(true);

      // Click "Group selected"
      await w.findAll("button").find((b) => b.text().includes("Group selected"))!.trigger("click");

      const emitted = lastEmitted(w);
      // b1 and b3 grouped, b2 remains standalone
      // Group inserted at position of first selected (index 0)
      expect(emitted.blocks).toHaveLength(2);
      expect(emitted.blocks[0].type).toBe("group");
      expect((emitted.blocks[0] as ConditionGroup).blocks).toHaveLength(2);
      expect(emitted.blocks[1].id).toBe("b2");
    });

    it("does not group when fewer than 2 blocks selected", async () => {
      const b1 = makeBlock({ id: "b1" });
      const b2 = makeBlock({ id: "b2" });
      const w = mountBuilder({ logic: "all", blocks: [b1, b2] });

      await w.findAll("button").find((b) => b.text().includes("Group"))!.trigger("click");

      // Select only one
      const checkboxes = w.findAll("input[type='checkbox']");
      await checkboxes[0].setValue(true);

      // Group selected button should be disabled
      const groupSelectedBtn = w.findAll("button").find((b) => b.text().includes("Group selected"));
      expect(groupSelectedBtn?.attributes("disabled")).toBeDefined();
    });
  });

  describe("updateTopLogic", () => {
    it("is not shown when less than 2 blocks", () => {
      const w = mountBuilder({ logic: "all", blocks: [makeBlock()] });
      expect(w.findComponent({ name: "LogicToggle" }).exists()).toBe(false);
    });

    it("is shown when 2+ blocks exist", () => {
      const w = mountBuilder({ logic: "all", blocks: [makeBlock({ id: "b1" }), makeBlock({ id: "b2" })] });
      expect(w.findComponent({ name: "LogicToggle" }).exists()).toBe(true);
    });

    it("emits updated logic when toggled", () => {
      const w = mountBuilder({ logic: "all", blocks: [makeBlock({ id: "b1" }), makeBlock({ id: "b2" })] });
      w.findComponent({ name: "LogicToggle" }).vm.$emit("update:logic", "any");
      const emitted = lastEmitted(w);
      expect(emitted.logic).toBe("any");
    });
  });

  describe("disabled state", () => {
    it("hides add button when disabled", () => {
      const w = mountBuilder({ logic: "all", blocks: [] }, { disabled: true });
      expect(w.findAll("button").some((b) => b.text().includes("Add block"))).toBe(false);
    });

    it("shows empty state text when disabled with no blocks", () => {
      const w = mountBuilder({ logic: "all", blocks: [] }, { disabled: true });
      expect(w.text()).toContain("No conditions set");
    });
  });
});
