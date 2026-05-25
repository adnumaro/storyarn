import { describe, expect, it } from "vitest";
import {
  isMovementPlayablePin,
  isMovementWalkableZone,
} from "../../../../modules/scenes/exploration/composables/useMovement";
import type { ExplorationPin, ExplorationZone } from "../../../../modules/scenes/exploration/types";

function pin(attrs: Partial<ExplorationPin> = {}): ExplorationPin {
  return {
    id: "pin-1",
    positionX: 5,
    positionY: 5,
    isPlayable: true,
    isLeader: true,
    visibility: "visible",
    ...attrs,
  };
}

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

describe("isMovementPlayablePin", () => {
  it("accepts visible playable pins", () => {
    expect(isMovementPlayablePin(pin())).toBe(true);
  });

  it("rejects non-playable, hidden, and disabled pins", () => {
    expect(isMovementPlayablePin(pin({ isPlayable: false }))).toBe(false);
    expect(isMovementPlayablePin(pin({ visibility: "hide" }))).toBe(false);
    expect(isMovementPlayablePin(pin({ visibility: "disable" }))).toBe(false);
  });
});
