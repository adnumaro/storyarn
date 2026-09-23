import { orderDecisions, shownRevision } from "@app/live/ideation/decisionStatus";
import type { DecisionRecord } from "@app/live/ideation/decisionTypes";
import type { Round } from "../types";
import { orderRounds } from "./bands";

/** Canvas units. The lane sits this far under a band's lowest note or frame. */
export const LANE_GAP = 72;
export const LANE_PAD = 24;
export const LANE_CARD_WIDTH = 320;
export const LANE_CARD_GAP = 20;
/** Until the canvas has measured a card, a two-line conclusion card is this tall. */
export const LANE_CARD_HEIGHT = 196;

export interface LaneCard {
  decision: DecisionRecord;
  x: number;
  y: number;
}
export interface LaneLayout {
  roundId: number;
  x: number;
  y: number;
  width: number;
  height: number;
  cards: LaneCard[];
}

/**
 * A decision lives in the band of its newest source round. A decision whose
 * round no longer exists, or never had one, joins the last band.
 */
export function decisionsByRound(decisions: DecisionRecord[], rounds: Round[]) {
  const ordered = orderRounds(rounds);
  const byNumber = new Map(ordered.map((round) => [round.number, round.id]));
  const fallback = ordered[ordered.length - 1]?.id ?? null;
  const { live, retired } = orderDecisions(decisions);
  const lanes = new Map<number, DecisionRecord[]>();
  for (const decision of [...live, ...retired]) {
    const number = shownRevision(decision).round?.number;
    const roundId = (number !== undefined && byNumber.get(number)) || fallback;
    if (roundId === null) continue;
    lanes.set(roundId, [...(lanes.get(roundId) ?? []), decision]);
  }
  return lanes;
}

/**
 * Cards read left to right in the order of the list: what waits for the reader,
 * what is still to apply, proposals, what is done, then what was retired. The
 * lane starts where the band's content starts and is as wide as its cards.
 */
export function layoutLane(
  roundId: number,
  decisions: DecisionRecord[],
  place: { top: number; bottom: number | null; left: number; cardHeight: number },
): LaneLayout {
  const y = place.top + (place.bottom ?? 0) + LANE_GAP;
  const x = place.left - LANE_PAD;
  const cards = decisions.map((decision, index) => ({
    decision,
    x: x + LANE_PAD + index * (LANE_CARD_WIDTH + LANE_CARD_GAP),
    y: y + LANE_PAD,
  }));
  return {
    roundId,
    x,
    y,
    width:
      LANE_PAD * 2 + decisions.length * LANE_CARD_WIDTH + (decisions.length - 1) * LANE_CARD_GAP,
    height: LANE_PAD * 2 + place.cardHeight,
    cards,
  };
}

/** How far below its header a band's lane ends, so the band grows around it. */
export function laneBottom(lane: LaneLayout, top: number) {
  return lane.y + lane.height - top;
}

/** The decisions each note supports directly, in the order of the list. */
export function decisionsByNote(decisions: DecisionRecord[]) {
  const { live, retired } = orderDecisions(decisions);
  const notes = new Map<number, DecisionRecord[]>();
  for (const decision of [...live, ...retired])
    for (const source of shownRevision(decision).sources)
      if (source.type === "idea" && source.id !== null && source.available)
        notes.set(source.id, [...(notes.get(source.id) ?? []), decision]);
  return notes;
}
