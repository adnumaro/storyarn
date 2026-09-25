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

function setup(lane: Round["decision_lane"] = {}, overrides: Partial<Round> = {}) {
  const source = ref(board({ rounds: [round({ id: 20, decision_lane: lane, ...overrides })] }));
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
      () => new Map([[20, 500]]),
    );
    return { history, lanes };
  })!;
  cleanup.push(() => scope.stop());
  const land = (place: Round["decision_lane"]) => {
    source.value = { ...source.value, rounds: [round({ id: 20, decision_lane: place })] };
  };
  // Answers the latest request and lets the board carry what it wrote.
  const confirm = async (place: Round["decision_lane"]) => {
    sent.at(-1)!.resolve({ status: "ok", value: {} });
    await flushPromises();
    land(place);
    await flushPromises();
  };
  return { source, sent, notify, land, confirm, ...result };
}

describe("moving a decision lane", () => {
  it("shows the move at once, writes it relative to the round header and keeps it once the board lands", async () => {
    const { lanes, sent, confirm } = setup();
    expect(lanes.places.value.size).toBe(0);
    const moved = lanes.move(20, { x: 40, y: 900 });
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
    expect(sent[0].event).toBe("move_decision_lane");
    expect(sent[0].payload).toEqual({ round_id: 20, x: 40, y: 400, version: 0 });
    await confirm({ x: 40, y: 400, version: 1 });
    await moved;
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
  });

  it("puts a rejected move back and says why", async () => {
    const { lanes, sent, notify, history } = setup({ x: 10, y: 20, version: 3 });
    const moved = lanes.move(20, { x: 300, y: 800 });
    expect(sent[0].payload).toMatchObject({ version: 3 });
    sent[0].resolve({ status: "error", code: "stale_decision_lane" });
    await moved;
    expect(notify).toHaveBeenCalledWith("stale_decision_lane");
    expect(lanes.places.value.get(20)).toEqual({ x: 10, y: 520 });
    expect(history.canUndo.value).toBe(false);
  });

  it("undoes a lane that had never moved back to its automatic place, and redoes the move", async () => {
    const { lanes, sent, confirm, history } = setup();
    const moved = lanes.move(20, { x: 40, y: 900 });
    await confirm({ x: 40, y: 400, version: 1 });
    await moved;

    const undone = history.undo();
    await flushPromises();
    expect(sent[1].payload).toEqual({ round_id: 20, x: null, y: null, version: 1 });
    await confirm({ version: 2 });
    await undone;
    expect(lanes.places.value.has(20)).toBe(false);

    const redone = history.redo();
    await flushPromises();
    expect(sent[2].payload).toEqual({ round_id: 20, x: 40, y: 400, version: 2 });
    await confirm({ x: 40, y: 400, version: 3 });
    await redone;
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
  });

  it("never undoes over someone else's move, even one that came back to the same spot", async () => {
    const { lanes, sent, confirm, land, history } = setup({ x: 0, y: 100, version: 1 });
    const moved = lanes.move(20, { x: 40, y: 900 });
    await confirm({ x: 40, y: 400, version: 2 });
    await moved;
    // A peer moves it away and back: same place, newer version.
    land({ x: 40, y: 400, version: 4 });
    await history.undo();
    expect(sent).toHaveLength(1);
    expect(lanes.places.value.get(20)).toEqual({ x: 40, y: 900 });
  });

  it("does nothing for a drop where it already sits, a reader who cannot edit or a private round", async () => {
    const stays = setup({ x: 0, y: 200, version: 1 });
    await stays.lanes.move(20, { x: 0, y: 700 });
    expect(stays.sent).toHaveLength(0);

    const reader = setup();
    reader.source.value = { ...reader.source.value, can_edit: false };
    expect(reader.lanes.movable(20)).toBe(false);
    await reader.lanes.move(20, { x: 5, y: 700 });
    expect(reader.sent).toHaveLength(0);

    const hidden = setup({}, { private: true });
    expect(hidden.lanes.movable(20)).toBe(false);
    await hidden.lanes.move(20, { x: 5, y: 700 });
    expect(hidden.sent).toHaveLength(0);
  });
});
