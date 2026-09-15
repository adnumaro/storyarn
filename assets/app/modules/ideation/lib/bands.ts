import type { Round } from "../types";

/** Canvas units. An empty band is this tall, and a band keeps this much room under its lowest content. */
export const BAND_MIN = 320;
export const BAND_PAD = 160;
/** Fallback note height until the canvas has measured one. */
export const NOTE_HEIGHT = 96;

/** Canvas y of every round header, keyed by round id. */
export type BandOffsets = Map<number, number>;

export function orderRounds(rounds: Round[]): Round[] {
  return [...rounds].sort((a, b) => a.number - b.number);
}

/**
 * Rounds are horizontal bands of one canvas, stacked in order. A band is as
 * tall as what it holds, so each header sits where the previous band's content
 * ends; `contentBottom` reports a round's lowest edge relative to its header.
 */
export function bandOffsets(
  rounds: Round[],
  contentBottom: (roundId: number) => number | null,
): BandOffsets {
  const offsets: BandOffsets = new Map();
  let top = 0;
  for (const round of orderRounds(rounds)) {
    offsets.set(round.id, top);
    const bottom = contentBottom(round.id);
    top += Math.max(BAND_MIN, bottom === null ? 0 : Math.ceil(bottom) + BAND_PAD);
  }
  return offsets;
}

export function sameOffsets(a: BandOffsets, b: BandOffsets): boolean {
  if (a.size !== b.size) return false;
  for (const [id, offset] of a) if (b.get(id) !== offset) return false;
  return true;
}

/** The band a canvas y falls in: the last header at or above it, else the first. */
export function bandAt(rounds: Round[], offsets: BandOffsets, y: number): number | null {
  let found: Round | null = null;
  for (const round of orderRounds(rounds)) {
    if (found === null || (offsets.get(round.id) ?? 0) <= y) found = round;
  }
  return found?.id ?? null;
}
