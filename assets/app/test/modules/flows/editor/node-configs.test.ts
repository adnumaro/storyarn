import { describe, expect, it } from "vitest";

import {
  createDynamicOutputs,
  needsRebuild,
  type NodeData,
} from "@modules/flows/editor/lib/node-configs";

function switchData(condition: NodeData["condition"] = {}): NodeData {
  return { switch_mode: true, condition };
}

describe("condition dynamic outputs", () => {
  it("keeps the fixed boolean outputs when switch mode is disabled", () => {
    expect(
      createDynamicOutputs("condition", {
        switch_mode: false,
        condition: { rules: [{ id: "case-a" }] },
      }),
    ).toBeNull();
  });

  it("creates one output per flat rule followed by the default output", () => {
    expect(
      createDynamicOutputs(
        "condition",
        switchData({
          rules: [{ id: "case-a" }, { id: "case-b" }],
        }),
      ),
    ).toEqual(["case-a", "case-b", "default"]);
  });

  it("uses block ids instead of flat rules and includes the default output", () => {
    expect(
      createDynamicOutputs(
        "condition",
        switchData({
          blocks: [{ id: "block-a" }, { id: "block-b" }],
          rules: [{ id: "legacy-rule" }],
        }),
      ),
    ).toEqual(["block-a", "block-b", "default"]);
  });

  it("does not expose legacy rule outputs when an empty blocks list is present", () => {
    expect(
      createDynamicOutputs(
        "condition",
        switchData({
          blocks: [],
          rules: [{ id: "legacy-rule" }],
        }),
      ),
    ).toEqual(["default"]);
  });

  it("exposes only the default output when a switch has no cases", () => {
    expect(createDynamicOutputs("condition", switchData())).toEqual(["default"]);
  });
});

describe("condition socket rebuilds", () => {
  it("rebuilds when toggling between boolean and switch mode", () => {
    expect(needsRebuild("condition", { switch_mode: false }, switchData())).toBe(true);
    expect(needsRebuild("condition", switchData(), { switch_mode: false })).toBe(true);
  });

  it("rebuilds when a case id changes without changing the case count", () => {
    const oldData = switchData({ rules: [{ id: "case-a" }, { id: "case-b" }] });
    const newData = switchData({ rules: [{ id: "case-a" }, { id: "case-c" }] });

    expect(needsRebuild("condition", oldData, newData)).toBe(true);
  });

  it("rebuilds when cases are reordered", () => {
    const oldData = switchData({ blocks: [{ id: "block-a" }, { id: "block-b" }] });
    const newData = switchData({ blocks: [{ id: "block-b" }, { id: "block-a" }] });

    expect(needsRebuild("condition", oldData, newData)).toBe(true);
  });

  it("does not rebuild when the dynamic output ids stay unchanged", () => {
    const oldData = switchData({ rules: [{ id: "case-a" }, { id: "case-b" }] });
    const newData = switchData({ rules: [{ id: "case-a" }, { id: "case-b" }] });

    expect(needsRebuild("condition", oldData, newData)).toBe(false);
  });
});
