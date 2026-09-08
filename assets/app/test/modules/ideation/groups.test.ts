import { describe, expect, it } from "vitest";
import { groupBounds, groupVisibility } from "@modules/ideation/lib/groups";
import { ideaGroup } from "./fixtures";

describe("group frame geometry", () => {
  it("bounds every member while positioning synthesis after the rightmost note", () => {
    const group = ideaGroup({ synthesis: "Conflicting loyalties" });
    const frame = groupBounds(group, [{ id: 10, height: 490 }]);
    expect(frame).toMatchObject({
      x: -18,
      y: -44,
      height: 582,
      notesWidth: 726,
      synthesisX: 726,
      width: 1058,
    });
    expect(frame.x + frame.synthesisX).toBeGreaterThan(400 + 280);
  });
  it("retains hidden-note geometry and explicitly marks partial groups", () => {
    const group = ideaGroup();
    const frame = groupBounds(group, [{ id: 10, canvas: { x: 25, y: 40 } }]);
    expect(frame.x + frame.width).toBe(708);
    expect(groupVisibility(group, [10])).toEqual({ visible: 1, total: 2, partial: true });
  });
  it("places synthesis below its sources when a neighboring note occupies the right edge", () => {
    const group = ideaGroup({
      idea_ids: [10],
      members: [ideaGroup().members[0]],
      synthesis: "Insight",
    });
    const frame = groupBounds(
      group,
      [{ id: 12, canvas: { x: 340, y: 20, width: 280 }, height: 500 }],
      260,
    );
    expect(frame.synthesisX).toBe(28);
    expect(frame.y + frame.synthesisY).toBeGreaterThanOrEqual(20 + 260 + 28);
    const note = { x: 340, y: 20, width: 280, height: 500 };
    expect(frame.x + frame.synthesisX + 304).toBeLessThan(note.x);
    expect(frame.height).toBeGreaterThanOrEqual(frame.synthesisY + 260 + 28);
  });
  it("tracks optimistic member movement and uses the retained anchor after separating notes", () => {
    const moved = groupBounds(ideaGroup(), [
      { id: 10, canvas: { x: 1010, y: 1020 } },
      { id: 11, canvas: { x: 1400, y: 1050 } },
    ]);
    expect(moved).toMatchObject({ x: 982, y: 956 });
    const standalone = ideaGroup({ idea_ids: [], members: [], synthesis: "Keep this insight" });
    expect(groupBounds(standalone)).toMatchObject({
      x: -18,
      y: -44,
      width: 360,
      notesWidth: 0,
      synthesisX: 28,
    });
  });
});
