import { computed, onScopeDispose, ref, watch } from "vue";
import type { Board, Request, Round } from "../types";
import type { BandOffsets } from "../lib/bands";
import type { Point } from "./useCanvasViewport";
import type { useCanvasHistory } from "./useCanvasHistory";

type History = ReturnType<typeof useCanvasHistory>;
interface Placement extends Point {
  version: number;
}

function stored(round: Round): Point | null {
  const { x, y } = round.decision_lane ?? {};
  return typeof x === "number" && typeof y === "number" ? { x, y } : null;
}
function samePoint(a: Point, b: Point) {
  return a.x === b.x && a.y === b.y;
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
  const pending = ref(new Map<number, Placement>());
  const allowed = computed(() => board().can_edit && board().session?.status === "open");
  const find = (id: number) => board().rounds.find((round) => round.id === id);
  const offsetOf = (id: number) => offsets().get(id) ?? 0;
  const versionOf = (round: Round) =>
    pending.value.get(round.id)?.version ?? round.decision_lane?.version ?? 0;
  const placeOf = (round: Round) => pending.value.get(round.id) ?? stored(round);

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

  async function write(roundId: number, point: Point, version: number) {
    pending.value.set(roundId, { ...point, version: version + 1 });
    const reply = await request<Placement>("move_decision_lane", {
      round_id: roundId,
      x: point.x,
      y: point.y,
      version,
    });
    if (reply.status === "ok") return true;
    pending.value.delete(roundId);
    notify(reply.status === "error" ? reply.code : "stale_decision_lane");
    return false;
  }

  /** Moves a lane between two absolute points; undo puts it back where it was. */
  async function move(roundId: number, point: Point, from: Point) {
    if (!allowed.value || history.busy.value) return;
    const round = find(roundId);
    if (!round) return;
    const before = { x: from.x, y: from.y - offsetOf(roundId) };
    const after = { x: point.x, y: point.y - offsetOf(roundId) };
    if (samePoint(before, after)) return;
    const moved = await history.run(() => write(roundId, after, versionOf(round)));
    if (!moved) return;
    // Someone else may have moved the lane since; history never overrides them.
    async function apply(target: Point, expected: Point) {
      const current = find(roundId);
      const place = current ? placeOf(current) : null;
      if (!current || !place || !samePoint(place, expected)) return false;
      return write(roundId, target, versionOf(current));
    }
    history.push({
      targets: () => [],
      undo: () => apply(before, after),
      redo: () => apply(after, before),
    });
  }

  onScopeDispose(() => pending.value.clear());
  return { places, allowed, move };
}
