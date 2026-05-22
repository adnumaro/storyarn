import { describe, expect, it } from "vitest";
import { isMovementWalkableZone } from "../../../../modules/scenes/exploration/composables/useMovement";
import type { ExplorationZone } from "../../../../modules/scenes/exploration/types";

function zone(attrs: Partial<ExplorationZone> = {}): ExplorationZone {
  return {
    id: "zone-1",
    actionType: "walkable",
    isWalkable: true,
    vertices: [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
    ],
    visibility: "visible",
    ...attrs,
  };
}

describe("isMovementWalkableZone", () => {
  it("accepts visible walkable zones with a polygon", () => {
    expect(isMovementWalkableZone(zone())).toBe(true);
  });

  it("rejects non-walkable action types even if the boolean flag is true", () => {
    expect(isMovementWalkableZone(zone({ actionType: "action", isWalkable: true }))).toBe(false);
  });

  it("rejects hidden zones and incomplete polygons", () => {
    expect(isMovementWalkableZone(zone({ visibility: "hide" }))).toBe(false);
    expect(isMovementWalkableZone(zone({ vertices: [{ x: 0, y: 0 }] }))).toBe(false);
  });
});
