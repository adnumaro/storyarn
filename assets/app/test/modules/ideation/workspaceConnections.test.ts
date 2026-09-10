import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import BrainstormingWorkspace from "@modules/ideation/BrainstormingWorkspace.vue";
import { Button } from "@components/ui/button";
import { createMockLive } from "../../setup";
import { board, idea } from "./fixtures";
import type { Board, Idea, ConnectionChange, ConnectionResult } from "@modules/ideation/types";

type ConnectionReply =
  | { status: "ok"; value: ConnectionResult }
  | { status: "error"; code: string };

const reveal = vi.fn();
const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  props: ["notes", "editingId", "permissions", "historyState", "selectedIds"],
  setup(_props, { expose }) {
    expose({ focus: vi.fn(), revealNote: reveal });
    return () => h("div");
  },
});
let wrapper: VueWrapper;
function workspace(overrides: Partial<Board> = {}, deferConnections = false) {
  vi.useFakeTimers();
  const live = createMockLive();
  const current = board({
    ideas: [idea({ canvas: { links: [], links_version: 0 } }), idea({ id: 11 }), idea({ id: 12 })],
    ...overrides,
  });
  const calls = vi.fn();
  const replies: Array<(value?: ConnectionReply) => void> = [];
  vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
    calls(event, payload);
    if (event === "update_idea_connections") {
      const changes = payload!.changes as ConnectionChange[];
      const result: ConnectionReply = {
        status: "ok",
        value: {
          changes,
          versions: (payload!.versions as Array<{ id: number; version: number }>).map((source) => ({
            ...source,
            version: source.version + 1,
          })),
        },
      };
      const reply = (value: ConnectionReply = result) => callback?.(value);
      if (deferConnections) replies.push(reply);
      else reply();
    } else if (event === "create_idea") {
      callback?.({
        status: "ok",
        value: idea({
          id: 30,
          title: null,
          body: String(payload!.body),
          canvas: payload!.canvas as Idea["canvas"],
        }),
      });
    }
  });
  wrapper = shallowMount(BrainstormingWorkspace, {
    props: { board: current, baseUrl: "/brainstorming" },
    global: {
      provide: { _live_vue: live },
      stubs: { BrainstormingCanvas: Canvas },
      renderStubDefaultSlot: true,
    },
  });
  async function reply(value?: ConnectionReply) {
    await flushPromises();
    const next = replies.shift();
    if (!next) throw new Error("No pending connection request");
    next(value);
    await flushPromises();
  }
  return { current, canvas: wrapper.getComponent(Canvas), live, calls, reply };
}
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
  reveal.mockClear();
});

describe("workspace connections", () => {
  it("executes undo pressed during an ordinary connection write after its acknowledgement", async () => {
    const { canvas, calls, reply } = workspace({}, true);
    canvas.vm.$emit("connect", 10, 11, true);
    await flushPromises();
    expect(calls).toHaveBeenCalledTimes(1);
    expect(canvas.props("historyState").busy).toBe(true);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(calls).toHaveBeenCalledTimes(1);
    await reply();
    expect(calls).toHaveBeenCalledTimes(2);
    expect(calls).toHaveBeenLastCalledWith(
      "update_idea_connections",
      expect.objectContaining({
        changes: [{ source_id: 10, target_id: 11, connected: false }],
        versions: [{ id: 10, version: 1 }],
      }),
    );
    await reply();
    expect(canvas.props("historyState")).toEqual({ canUndo: false, canRedo: true, busy: false });
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([]);
  });
  it("cancels queued undo if a new connection becomes uncertain and retries that exact write", async () => {
    const { canvas, calls, reply } = workspace({}, true);
    canvas.vm.$emit("connect", 10, 11, true);
    await reply();
    canvas.vm.$emit("connect", 10, 12, true);
    await flushPromises();
    const uncertainWrite = structuredClone(calls.mock.calls[1][1]);
    canvas.vm.$emit("undo");
    canvas.vm.$emit("undo");
    await reply({ status: "error", code: "unavailable" });
    expect(calls).toHaveBeenCalledTimes(2);
    expect(canvas.props("historyState").canUndo).toBe(true);
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([11]);

    const retry = wrapper.findAllComponents(Button).find((button) => button.text() === "Retry");
    expect(retry).toBeDefined();
    await retry!.trigger("click");
    await flushPromises();
    expect(calls.mock.calls[2]).toEqual(["update_idea_connections", uncertainWrite]);
    await reply();
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([
      11, 12,
    ]);
    canvas.vm.$emit("undo");
    await reply();
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([11]);
  });
  it("keeps an unavailable undo retryable with the same request key and payload", async () => {
    const { canvas, calls, reply } = workspace({}, true);
    canvas.vm.$emit("connect", 10, 11, true);
    await reply();
    canvas.vm.$emit("undo");
    await flushPromises();
    const attemptedUndo = structuredClone(calls.mock.calls[1][1]);
    canvas.vm.$emit("undo");
    await reply({ status: "error", code: "unavailable" });
    expect(calls).toHaveBeenCalledTimes(2);
    expect(canvas.props("historyState")).toEqual({ canUndo: true, canRedo: false, busy: false });
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(calls.mock.calls[2]).toEqual(["update_idea_connections", attemptedUndo]);
    await reply();
    expect(canvas.props("historyState")).toEqual({ canUndo: false, canRedo: true, busy: false });
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([]);
  });
  it("does not send queued undo or redo after unmount when an old acknowledgement arrives", async () => {
    const { canvas, calls, reply } = workspace({}, true);
    canvas.vm.$emit("connect", 10, 11, true);
    await reply();
    canvas.vm.$emit("connect", 10, 12, true);
    await reply();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(calls).toHaveBeenCalledTimes(3);
    canvas.vm.$emit("undo");
    canvas.vm.$emit("redo");
    await flushPromises();
    expect(calls).toHaveBeenCalledTimes(3);
    wrapper.unmount();
    await reply();
    expect(calls).toHaveBeenCalledTimes(3);
  });
  it("connects from the selected origin in one action and undoes the whole batch", async () => {
    const { canvas, calls } = workspace();
    canvas.vm.$emit("connectSelection", [11, 10, 12], true);
    await flushPromises();
    expect(calls).toHaveBeenCalledWith(
      "update_idea_connections",
      expect.objectContaining({
        changes: [
          { source_id: 11, target_id: 10, connected: true },
          { source_id: 11, target_id: 12, connected: true },
        ],
      }),
    );
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(calls).toHaveBeenLastCalledWith(
      "update_idea_connections",
      expect.objectContaining({
        changes: [
          { source_id: 11, target_id: 10, connected: false },
          { source_id: 11, target_id: 12, connected: false },
        ],
      }),
    );
    expect(canvas.props("historyState").canUndo).toBe(false);
    canvas.vm.$emit("redo");
    await flushPromises();
    expect(canvas.props("notes").find((note: Idea) => note.id === 11).canvas.links).toEqual([
      10, 12,
    ]);
  });
  it("disconnects both directions within the selection without touching outside edges", async () => {
    const { canvas, calls } = workspace({
      ideas: [
        idea({ canvas: { links: [11, 12] } }),
        idea({ id: 11, canvas: { links: [10] } }),
        idea({ id: 12 }),
      ],
    });
    canvas.vm.$emit("connectSelection", [10, 11], false);
    await flushPromises();
    expect(calls).toHaveBeenCalledWith(
      "update_idea_connections",
      expect.objectContaining({
        changes: [
          { source_id: 10, target_id: 11, connected: false },
          { source_id: 11, target_id: 10, connected: false },
        ],
      }),
    );
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toEqual([12]);
  });
  it("opens a connected draft in place and empty cancellation can be undone and redone", async () => {
    const { canvas, calls } = workspace();
    canvas.vm.$emit("addConnected", [10, 11], { x: 800, y: 0 });
    await flushPromises();
    const id = canvas.props("editingId");
    expect(id).toBeLessThan(0);
    expect(reveal).toHaveBeenCalledWith(
      expect.objectContaining({ id, canvas: expect.objectContaining({ x: 800, y: 0 }) }),
    );
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toContain(id);
    expect(calls).not.toHaveBeenCalled();
    canvas.vm.$emit("finish");
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(3);
    canvas.vm.$emit("undo");
    await flushPromises();
    canvas.vm.$emit("redo");
    await flushPromises();
    const restored = canvas.props("notes").find((note: Idea) => note.id < 0);
    expect(restored).toBeDefined();
    expect(canvas.props("notes").find((note: Idea) => note.id === 10).canvas.links).toContain(
      restored.id,
    );
    canvas.vm.$emit("change", restored.id, "<p>A consequence</p>");
    await vi.advanceTimersByTimeAsync(800);
    await flushPromises();
    expect(calls).toHaveBeenCalledWith(
      "create_idea",
      expect.objectContaining({
        connection: { source_ids: [10, 11] },
        body: "<p>A consequence</p>",
      }),
    );
  });
  it("preserves a single manual connection as a normal history action", async () => {
    const { canvas, calls } = workspace();
    canvas.vm.$emit("connect", 10, 11, true);
    await flushPromises();
    expect(calls).toHaveBeenCalledWith("update_idea_connections", expect.anything());
    expect(canvas.props("historyState").canUndo).toBe(true);
  });
  it("rejects connected creation when contributions close, but keeps existing connections editable", async () => {
    const { canvas, calls } = workspace({
      session: { ...board().session!, contributions_open: false },
    });
    canvas.vm.$emit("addConnected", [10], { x: 800, y: 0 });
    await flushPromises();
    expect(canvas.props("editingId")).toBeNull();
    expect(calls).not.toHaveBeenCalled();
    canvas.vm.$emit("connectSelection", [10, 11], true);
    await flushPromises();
    expect(calls).toHaveBeenCalledWith("update_idea_connections", expect.anything());
  });
});
