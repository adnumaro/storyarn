import { computed, onScopeDispose, ref, watch } from "vue";
import type { Board, Request, Round } from "../types";
import type { BandOffsets } from "../lib/bands";
import type { Point } from "./useCanvasViewport";
import type { useCanvasHistory } from "./useCanvasHistory";

type History = ReturnType<typeof useCanvasHistory>;
/** Where a lane goes; null is its automatic place under the band's content. */
type Place = Point | null;
interface Pending {
  place: Place;
  version: number;
}

function stored(round: Round): Place {
  const { x, y } = round.decision_lane ?? {};
  return typeof x === "number" && typeof y === "number" ? { x, y } : null;
}
function samePlace(a: Place, b: Place) {
  return a === b || (a !== null && b !== null && a.x === b.x && a.y === b.y);
}

/**
 * Where each round's decision lane sits once someone moved it. Board data and
 * writes keep positions relative to the round header, like notes and groups;
 * the canvas reads absolute ones. A move shows at once and stays until the
 * board carries the version it wrote.
 */
export function useDecisionLanes(
  board: () => Board,
  request: Request,
  history: History,
  notify: (code: string | null) => void,
  offsets: () => BandOffsets = () => new Map(),
) {
  const pending = ref(new Map<number, Pending>());
  const allowed = computed(() => board().can_edit && board().session?.status === "open");
  const find = (id: number) => board().rounds.find((round) => round.id === id);
  const offsetOf = (id: number) => offsets().get(id) ?? 0;
  const versionOf = (round: Round) =>
    pending.value.get(round.id)?.version ?? round.decision_lane?.version ?? 0;
  const placeOf = (round: Round) =>
    pending.value.has(round.id) ? pending.value.get(round.id)!.place : stored(round);
  /** A private round stays hidden until its reveal, so nobody arranges it. */
  const movable = (roundId: number) => {
    const round = find(roundId);
    return allowed.value && !!round && !round.private;
  };

  const places = computed(() => {
    const result = new Map<number, Point>();
    for (const round of board().rounds) {
      const place = placeOf(round);
      if (place) result.set(round.id, { x: place.x, y: place.y + offsetOf(round.id) });
    }
    return result;
  });

  watch(
    () => board().rounds.map((round) => [round.id, round.decision_lane?.version ?? 0]),
    () => {
      for (const [id, move] of pending.value) {
        const round = find(id);
        if (!round || (round.decision_lane?.version ?? 0) >= move.version) pending.value.delete(id);
      }
    },
  );
  watch([() => board().epoch, () => board().session?.id], () => pending.value.clear());

  async function write(roundId: number, place: Place, version: number) {
    pending.value.set(roundId, { place, version: version + 1 });
    const reply = await request<Point & { version: number }>("move_decision_lane", {
      round_id: roundId,
      x: place?.x ?? null,
      y: place?.y ?? null,
      version,
    });
    if (reply.status === "ok") return true;
    pending.value.delete(roundId);
    notify(reply.status === "error" ? reply.code : "stale_decision_lane");
    return false;
  }

  /**
   * Moves a lane to an absolute point. Undo puts it back where it was, back in
   * its automatic place if it had never been moved.
   */
  async function move(roundId: number, point: Point) {
    const round = find(roundId);
    if (!round || !movable(roundId) || history.busy.value) return;
    const before = placeOf(round);
    const after = { x: point.x, y: point.y - offsetOf(roundId) };
    if (samePlace(before, after)) return;
    let version = versionOf(round);
    if (!(await history.run(() => write(roundId, after, version)))) return;
    version += 1;
    // Each step expects the version the previous one wrote: a move by anyone
    // else in between, even back to the same spot, ends this history.
    async function apply(target: Place) {
      const current = find(roundId);
      if (!current || versionOf(current) !== version) return false;
      if (!(await write(roundId, target, version))) return false;
      version += 1;
      return true;
    }
    history.push({
      targets: () => [],
      undo: () => apply(before),
      redo: () => apply(after),
    });
  }

  onScopeDispose(() => pending.value.clear());
  return { places, movable, move };
}
