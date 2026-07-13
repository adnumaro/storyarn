import { describe, expect, it } from "vitest";
import {
  findPartyWalkablePath,
  isMovementPlayablePin,
  isMovementWalkableZone,
} from "../../../../modules/scenes/exploration/composables/useMovement";
import { isSegmentInWalkableArea } from "../../../../modules/scenes/exploration/lib/walkablePath";
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

describe("findPartyWalkablePath", () => {
  const concaveZone = zone({
    vertices: [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 7, y: 10 },
      { x: 7, y: 3 },
      { x: 3, y: 3 },
      { x: 3, y: 10 },
      { x: 0, y: 10 },
    ],
  });

  it("routes followers around blocked space", () => {
    const start = { x: 1, y: 8 };
    const route = findPartyWalkablePath(start, { x: 9, y: 8 }, { x: 9, y: 7 }, [concaveZone]);

    expect(route).toEqual([
      { x: 3, y: 3 },
      { x: 7, y: 3 },
      { x: 9, y: 8 },
    ]);

    let segmentStart = start;
    for (const waypoint of route || []) {
      expect(isSegmentInWalkableArea(segmentStart, waypoint, [concaveZone])).toBe(true);
      segmentStart = waypoint;
    }
  });

  it("falls back to the leader target when the formation offset is outside", () => {
    const route = findPartyWalkablePath({ x: 1, y: 1 }, { x: -2, y: 1 }, { x: 2, y: 2 }, [
      concaveZone,
    ]);

    expect(route).toEqual([{ x: 2, y: 2 }]);
  });
});
