import { describe, expect, it } from "vitest";
import {
  LANE_CARD_GAP,
  LANE_CARD_WIDTH,
  LANE_GAP,
  LANE_PAD,
  decisionsByNote,
  decisionsByRound,
  laneBottom,
  layoutLane,
} from "@modules/ideation/lib/decisionLanes";
import { accepted, decision, revision, source } from "../../live/ideation/decisionFixtures";
import { round } from "./fixtures";

const rounds = [round({ id: 21, number: 2 }), round({ id: 20, number: 1 })];

describe("decisionsByRound", () => {
  it("places each decision in the band of its newest source round", () => {
    const first = decision({ id: 1, proposal: revision({ round: { number: 1, prompt: "" } }) });
    const second = decision({ id: 2, proposal: revision({ round: { number: 2, prompt: "" } }) });
    const lanes = decisionsByRound([second, first], rounds);
    expect(lanes.get(20)?.map((item) => item.id)).toEqual([1]);
    expect(lanes.get(21)?.map((item) => item.id)).toEqual([2]);
  });

  it("sends a decision without a surviving round to the last band, retired decisions last", () => {
    const orphan = decision({ id: 3, proposal: revision({ round: null }) });
    const gone = decision({ id: 4, proposal: revision({ round: { number: 9, prompt: "" } }) });
    const withdrawn = decision({
      id: 5,
      status: "withdrawn",
      proposal: revision({ round: { number: 2, prompt: "" } }),
    });
    const lanes = decisionsByRound([withdrawn, orphan, gone], rounds);
    expect(lanes.get(21)?.map((item) => item.id)).toEqual([3, 4, 5]);
    expect(lanes.has(20)).toBe(false);
  });

  it("has no lane without a band", () => {
    expect(decisionsByRound([decision()], []).size).toBe(0);
  });
});

describe("layoutLane", () => {
  it("sits under the band's content and is as wide as its cards", () => {
    const lane = layoutLane(20, [decision({ id: 1 }), decision({ id: 2 })], {
      top: 100,
      bottom: 400,
      left: 60,
      cardHeight: 180,
    });
    expect(lane.y).toBe(100 + 400 + LANE_GAP);
    expect(lane.x).toBe(60 - LANE_PAD);
    expect(lane.width).toBe(LANE_PAD * 2 + LANE_CARD_WIDTH * 2 + LANE_CARD_GAP);
    expect(lane.height).toBe(LANE_PAD * 2 + 180);
    expect(lane.cards.map((card) => card.x)).toEqual([60, 60 + LANE_CARD_WIDTH + LANE_CARD_GAP]);
    expect(lane.cards.every((card) => card.y === lane.y + LANE_PAD)).toBe(true);
    expect(laneBottom(lane, 100)).toBe(400 + LANE_GAP + LANE_PAD * 2 + 180);
  });

  it("starts right under the header of an empty band", () => {
    const lane = layoutLane(20, [decision()], { top: 0, bottom: null, left: 0, cardHeight: 100 });
    expect(lane.y).toBe(LANE_GAP);
  });

  it("sits where someone left it once moved, whatever the band holds", () => {
    const lane = layoutLane(20, [decision({ id: 1 })], {
      top: 100,
      bottom: 400,
      left: 60,
      cardHeight: 180,
      at: { x: -30, y: 900 },
    });
    expect([lane.x, lane.y]).toEqual([-30, 900]);
    expect(lane.cards[0]).toMatchObject({ x: -30 + LANE_PAD, y: 900 + LANE_PAD });
  });
});

describe("decisionsByNote", () => {
  it("lists the decisions each available note supports, in list order", () => {
    const proposal = decision({ id: 1, proposal: revision({ sources: [source({ id: 10 })] }) });
    const agreed = accepted({ id: 2 });
    const group = decision({
      id: 3,
      proposal: revision({ sources: [source({ type: "group", id: 10 })] }),
    });
    const hidden = decision({
      id: 4,
      proposal: revision({ sources: [source({ id: 11, available: false })] }),
    });
    const notes = decisionsByNote([agreed, proposal, group, hidden]);
    // The proposal waits for the reader, so it leads the one still to apply.
    expect(notes.get(10)?.map((item) => item.id)).toEqual([1, 2]);
    expect(notes.has(11)).toBe(false);
  });
});
