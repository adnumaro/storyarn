import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick, ref, type App } from "vue";
import { flushPromises } from "@vue/test-utils";
import { withSetup } from "../../setup";
import { useCanvasConnections } from "@modules/ideation/composables/useCanvasConnections";
import { useCanvasNotes } from "@modules/ideation/composables/useCanvasNotes";
import { useCanvasHistory } from "@modules/ideation/composables/useCanvasHistory";
import type {
  ConnectionChange,
  ConnectionResult,
  CreatedIdea,
  Reply,
  Request,
} from "@modules/ideation/types";
import { board, idea } from "./fixtures";

const mounted: App[] = [];
const link = (target = 11, connected = true, source = 10): ConnectionChange => ({
  source_id: source,
  target_id: target,
  connected,
});
const result = (changes: ConnectionChange[], version: number, source = 10): ConnectionResult => ({
  changes,
  versions: [{ id: source, version }],
});
async function flush() {
  await flushPromises();
}
function setup() {
  const current = ref(
    board({
      ideas: [10, 11, 12, 13].map((id) =>
        idea({
          id,
          canvas: { x: id * 100, y: 10, width: 280, version: 20, links: [], links_version: 0 },
        }),
      ),
    }),
  );
  const replies: ((reply: Reply<unknown>) => void)[] = [];
  const request = vi.fn(
    (_event: string, _payload: Record<string, unknown>, _context?: unknown) =>
      new Promise<Reply<unknown>>((resolve) => replies.push(resolve)),
  );
  const failure = ref<string | null>(null);
  const historyError = vi.fn();
  const { result: state, app } = withSetup(() => {
    const context = () => ({ epoch: current.value.epoch, session_id: current.value.session!.id });
    const history = useCanvasHistory(historyError, () =>
      ["offline", "unavailable"].includes(failure.value ?? ""),
    );
    let connections!: ReturnType<typeof useCanvasConnections>;
    const notes = useCanvasNotes(
      () => current.value,
      request as Request,
      context,
      vi.fn(),
      (created) => connections.created(created),
    );
    connections = useCanvasConnections({
      notes,
      request: request as Request,
      context,
      history,
      allowed: () => current.value.can_edit,
      notify: (code) => {
        failure.value = code;
      },
    });
    return { notes, history, connections };
  });
  mounted.push(app);
  async function reply(task: Promise<unknown>, response: Reply<unknown>) {
    await flush();
    replies.at(-1)!(response);
    await task;
  }
  return { ...state, current, request, replies, failure, historyError, reply };
}
afterEach(() => {
  for (const app of mounted.splice(0)) app.unmount();
});

describe("acknowledged connection history", () => {
  it("shares restored tokens across undo B, undo A, redo A and redo B", async () => {
    const state = setup();
    await state.reply(state.connections.change([link(11)]), {
      status: "ok",
      value: result([link(11)], 1),
    });
    await state.reply(state.connections.change([link(12)]), {
      status: "ok",
      value: result([link(12)], 2),
    });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(12, false)], 3) });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(11, false)], 4) });
    expect(state.notes.find(10)?.canvas?.links).toEqual([]);
    await state.reply(state.history.redo(), { status: "ok", value: result([link(11)], 5) });
    await state.reply(state.history.redo(), { status: "ok", value: result([link(12)], 6) });
    expect(state.request.mock.calls.map((call) => call[1].versions)).toEqual(
      [0, 1, 2, 3, 4, 5].map((version) => [{ id: 10, version }]),
    );
    expect(state.notes.find(10)?.canvas).toMatchObject({
      links: [11, 12],
      links_version: 6,
      version: 20,
    });
    expect(state.historyError).not.toHaveBeenCalled();
  });

  it("does not rebase an old undo onto a remote ABA change", async () => {
    const state = setup();
    await state.reply(state.connections.change([link()]), {
      status: "ok",
      value: result([link()], 1),
    });
    Object.assign(state.current.value.ideas[0].canvas!, { links: [], links_version: 2 });
    await nextTick();
    Object.assign(state.current.value.ideas[0].canvas!, { links: [11], links_version: 3 });
    await state.reply(state.history.undo(), { status: "error", code: "stale_connections" });
    expect(state.request.mock.calls[1][1]).toMatchObject({
      changes: [link(11, false)],
      versions: [{ id: 10, version: 1 }],
    });
    expect(state.notes.find(10)?.canvas).toMatchObject({ links: [11], links_version: 3 });
    expect(state.history.canRedo.value).toBe(false);
    expect(state.history.canUndo.value).toBe(false);
  });

  it("uses the independent connection version after a remote position update", async () => {
    const state = setup();
    Object.assign(state.current.value.ideas[0].canvas!, { x: 900, version: 99 });
    await state.reply(state.connections.change([link()]), {
      status: "ok",
      value: result([link()], 1),
    });
    expect(state.request.mock.calls[0][1].versions).toEqual([{ id: 10, version: 0 }]);
    expect(state.notes.find(10)?.canvas).toMatchObject({ x: 900, version: 99, links_version: 1 });
  });

  it("records only effective changes and omits a wholly idempotent write from undo", async () => {
    const state = setup();
    Object.assign(state.current.value.ideas[0].canvas!, { links: [11], links_version: 4 });
    await state.reply(state.connections.change([link(11), link(12)]), {
      status: "ok",
      value: result([link(12)], 5),
    });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(12, false)], 6) });
    expect(state.request.mock.calls[1][1]).toMatchObject({ changes: [link(12, false)] });
    expect(state.notes.find(10)?.canvas?.links).toEqual([11]);
    await state.reply(state.connections.change([link(11)]), { status: "ok", value: result([], 6) });
    expect(state.history.canUndo.value).toBe(false);
  });

  it.each(["offline", "unavailable"])(
    "retries an uncertain %s submission verbatim and adds one history command",
    async (code) => {
      const state = setup();
      await state.reply(state.connections.change([link()]), { status: "error", code });
      const original = structuredClone(state.request.mock.calls[0]);
      expect(state.connections.pending.value).not.toBeNull();
      await state.connections.change([link(12)]);
      expect(state.failure.value).toBe("connections_pending");
      expect(state.request).toHaveBeenCalledTimes(1);
      await state.reply(state.connections.retry(), { status: "ok", value: result([link()], 1) });
      expect(state.request.mock.calls[1]).toEqual(original);
      expect(state.connections.pending.value).toBeNull();
      await state.connections.retry();
      expect(state.request).toHaveBeenCalledTimes(2);
      await state.reply(state.history.undo(), {
        status: "ok",
        value: result([link(11, false)], 2),
      });
      expect(state.history.canUndo.value).toBe(false);
      expect(state.history.canRedo.value).toBe(true);
    },
  );

  it("retries an uncertain undo using the same key even after receiving the committed projection", async () => {
    const state = setup();
    await state.reply(state.connections.change([link()]), {
      status: "ok",
      value: result([link()], 1),
    });
    await state.reply(state.history.undo(), { status: "error", code: "offline" });
    const original = structuredClone(state.request.mock.calls[1]);
    Object.assign(state.current.value.ideas[0].canvas!, { links: [], links_version: 2 });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(11, false)], 2) });
    expect(state.request.mock.calls[2]).toEqual(original);
    expect(state.history.canUndo.value).toBe(false);
    await state.reply(state.history.redo(), { status: "ok", value: result([link()], 3) });
    expect(state.request.mock.calls[3][1].versions).toEqual([{ id: 10, version: 2 }]);
  });

  it("clears a definitive rejection so a corrected action can use a fresh request", async () => {
    const state = setup();
    await state.reply(state.connections.change([link()]), {
      status: "error",
      code: "stale_connections",
    });
    expect(state.connections.pending.value).toBeNull();
    expect(state.history.canUndo.value).toBe(false);
    await state.reply(state.connections.change([link(12)]), {
      status: "ok",
      value: result([link(12)], 1),
    });
    expect(state.request.mock.calls[1][1].request_key).not.toBe(
      state.request.mock.calls[0][1].request_key,
    );
  });

  it("does not let an old acknowledgement touch a new session's projection, history or pending action", async () => {
    const state = setup();
    const previous = state.connections.change([link()]);
    await flush();
    state.connections.reset();
    state.history.clear();
    state.notes.reset(false);
    state.current.value.epoch = "new-session";
    state.current.value.session!.id = 2;
    const fresh = state.connections.change([link(12)]);
    await flush();
    const freshPending = state.connections.pending.value;
    state.replies[0]({ status: "ok", value: result([link()], 1) });
    await previous;
    expect(state.connections.pending.value).toBe(freshPending);
    expect(state.history.busy.value).toBe(true);
    expect(state.history.canUndo.value).toBe(false);
    expect(state.notes.find(10)?.canvas?.links).toEqual([]);
    state.replies[1]({ status: "ok", value: result([link(12)], 1) });
    await fresh;
    expect(state.notes.find(10)?.canvas?.links).toEqual([12]);
    expect(state.history.canUndo.value).toBe(true);
  });

  it.each([
    { before: 1, expected: 2 },
    { before: 0, expected: 1 },
  ])(
    "advances an older token only when a creation proves continuity: %j",
    async ({ before, expected }) => {
      const state = setup();
      await state.reply(state.connections.change([link()]), {
        status: "ok",
        value: result([link()], 1),
      });
      const receipt: CreatedIdea = {
        ...idea({ id: 13 }),
        connected_from: [{ id: 10, before_version: before, version: 2 }],
      };
      state.notes.acknowledgeConnections(result([link(13)], 2));
      state.connections.created(receipt);
      await state.reply(
        state.history.undo(),
        before === 1
          ? { status: "ok", value: result([link(11, false)], 3) }
          : { status: "error", code: "stale_connections" },
      );
      expect(state.request.mock.calls[1][1].versions).toEqual([{ id: 10, version: expected }]);
      expect(state.notes.find(10)?.canvas?.links).toContain(13);
    },
  );

  it("does not detach the shared undo token when an older creation receipt arrives late", async () => {
    const state = setup();
    await state.reply(state.connections.change([link(11)]), {
      status: "ok",
      value: result([link(11)], 1),
    });
    await state.reply(state.connections.change([link(12)]), {
      status: "ok",
      value: result([link(12)], 2),
    });
    state.connections.created({
      ...idea({ id: 30 }),
      connected_from: [{ id: 10, before_version: 0, version: 1 }],
    });
    await state.reply(state.connections.change([link(13)]), {
      status: "ok",
      value: result([link(13)], 3),
    });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(13, false)], 4) });
    await state.reply(state.history.undo(), { status: "ok", value: result([link(12, false)], 5) });
    expect(state.request.mock.calls[4][1].versions).toEqual([{ id: 10, version: 4 }]);
  });
});
