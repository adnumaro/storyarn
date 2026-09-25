import { afterEach, describe, expect, it, vi } from "vitest";
import { effectScope, ref } from "vue";
import { flushPromises } from "@vue/test-utils";
import { useCanvasHistory } from "@modules/ideation/composables/useCanvasHistory";
import { useDecisionLanes } from "@modules/ideation/composables/useDecisionLanes";
import type { Reply, Request, Round } from "@modules/ideation/types";
import { board, round } from "./fixtures";

interface Sent {
  event: string;
  payload: { [key: string]: unknown };
  resolve: (reply: Reply<unknown>) => void;
}

const cleanup: Array<() => void> = [];
afterEach(() => cleanup.splice(0).forEach((fn) => fn()));

function setup(lane: Round["decision_lane"] = {}) {
  const source = ref(board({ rounds: [round({ id: 20, decision_lane: lane })] }));
  const sent: Sent[] = [];
  const send: Request = <T>(event: string, payload: { [key: string]: unknown }) =>
    new Promise<Reply<T>>((resolve) =>
      sent.push({ event, payload, resolve: (reply) => resolve(reply as Reply<T>) }),
    );
  const notify = vi.fn();
  const scope = effectScope();
  const result = scope.run(() => {
    const history = useCanvasHistory(vi.fn());
    // The round header sits 500 canvas units down; stored places are relative to it.
    const lanes = useDecisionLanes(
      () => source.value,
      send,
      history,
      notify,
      () => {
        return new Map([[20, 500]]);
      },
    );
    return { history, lanes };
  })!;
  cleanup.push(() => scope.stop());
  const land = (place: Round["decision_lane"]) => {
    source.value = { ...source.value, rounds: [round({ id: 20, decision_lane: place })] };
  };
  return { source, sent, notify, land, ...result };
}

describe("moving a decision lane", () => {
  it("shows the move at once, writes it relative to the round header and keeps it once the board lands", async () => {
    const { lanes, sent, land } = setup();
    expect(lanes.places.value.size).toBe(0);
    const moved = lanes.move(20, { x: 40, y: 900 }, { x: 0, y: 700 });
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
    expect(sent[0].event).toBe("move_decision_lane");
    expect(sent[0].payload).toEqual({ round_id: 20, x: 40, y: 400, version: 0 });
    sent[0].resolve({ status: "ok", value: { x: 40, y: 400, version: 1 } });
    await moved;
    land({ x: 40, y: 400, version: 1 });
    await flushPromises();
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
  });

  it("puts a rejected move back and says why", async () => {
    const { lanes, sent, notify, history } = setup({ x: 10, y: 20, version: 3 });
    const moved = lanes.move(20, { x: 300, y: 800 }, { x: 10, y: 520 });
    expect(sent[0].payload).toMatchObject({ version: 3 });
    sent[0].resolve({ status: "error", code: "stale_decision_lane" });
    await moved;
    expect(notify).toHaveBeenCalledWith("stale_decision_lane");
    expect(lanes.places.value.get(20)).toEqual({ x: 10, y: 520 });
    expect(history.canUndo.value).toBe(false);
  });

  it("undoes to where the lane was, unless someone moved it since", async () => {
    const { lanes, sent, land, history } = setup();
    const moved = lanes.move(20, { x: 40, y: 900 }, { x: 0, y: 700 });
    sent[0].resolve({ status: "ok", value: {} });
    await moved;
    land({ x: 40, y: 400, version: 1 });
    await flushPromises();

    const undone = history.undo();
    await flushPromises();
    expect(sent[1].payload).toEqual({ round_id: 20, x: 0, y: 200, version: 1 });
    sent[1].resolve({ status: "ok", value: {} });
    await undone;
    land({ x: 0, y: 200, version: 2 });
    await flushPromises();
    expect(lanes.places.value.get(20)).toEqual({ x: 0, y: 700 });

    // A peer moves it; redoing must not take it back from them.
    land({ x: 900, y: 10, version: 3 });
    await history.redo();
    expect(sent).toHaveLength(2);
    expect(lanes.places.value.get(20)).toEqual({ x: 900, y: 510 });
  });

  it("does nothing for a drop where it started or for a reader who cannot edit", async () => {
    const { lanes, sent, source } = setup();
    await lanes.move(20, { x: 0, y: 700 }, { x: 0, y: 700 });
    source.value = { ...source.value, can_edit: false };
    await lanes.move(20, { x: 5, y: 700 }, { x: 0, y: 700 });
    expect(sent).toHaveLength(0);
  });
});
