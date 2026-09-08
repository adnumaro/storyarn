import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, nextTick } from "vue";
import BrainstormingWorkspace from "@modules/ideation/BrainstormingWorkspace.vue";
import { createMockLive } from "../../setup";
import { board, idea, round } from "./fixtures";
import type { Board, Idea } from "@modules/ideation/types";

const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  props: ["notes", "editingId", "permissions", "historyState", "collaboration", "selectedIds"],
  setup(_props, { expose }) {
    expose({ focus: vi.fn() });
    return () => h("div");
  },
});
let wrapper: VueWrapper;
function workspace(serialize = (body: string) => body, overrides: Partial<Board> = {}) {
  vi.useFakeTimers();
  const live = createMockLive();
  const current = board({ ideas: [idea(), idea({ id: 11, body: "<p>Second</p>" })], ...overrides });
  const save = vi.fn();
  vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
    if (event === "save_idea") {
      save(payload);
      callback?.({
        status: "ok",
        value: idea({
          ...current.ideas.find((note) => note.id === payload!.idea_id),
          ...payload,
          body: serialize(String(payload!.body)),
          id: payload!.idea_id,
          revision: Number(payload!.revision) + 1,
        } as Partial<Idea>),
      });
    }
  });
  wrapper = shallowMount(BrainstormingWorkspace, {
    props: { board: current, baseUrl: "/brainstorming" },
    global: { provide: { _live_vue: live }, stubs: { BrainstormingCanvas: Canvas } },
  });
  const canvas = wrapper.getComponent(Canvas);
  return { current, canvas, save, live };
}
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("workspace editing transitions", () => {
  it("does not promise editing to viewers or show the contributions banner on archived sessions", async () => {
    const session = { ...board().session!, contributions_open: false };
    workspace((body) => body, { session, can_edit: false });
    expect(wrapper.get("#brainstorming-contributions-closed").text()).toBe(
      "New contributions are closed.",
    );
    await wrapper.setProps({ board: board({ session: { ...session, status: "archived" } }) });
    expect(wrapper.find("#brainstorming-contributions-closed").exists()).toBe(false);
  });

  it("keeps an in-progress edit when contributions close and blocks add, duplicate and paste", async () => {
    const { current, canvas, live } = workspace();
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Keep writing this note</p>");
    await wrapper.setProps({
      board: { ...current, session: { ...current.session!, contributions_open: false } },
    });
    expect(canvas.props("editingId")).toBe(10);
    expect(canvas.props("permissions").edit).toBe(true);
    expect(canvas.props("permissions").create).toBe(false);
    expect(canvas.props("notes")[0].body).toBe("<p>Keep writing this note</p>");
    canvas.vm.$emit("add", { x: 10, y: 20 });
    canvas.vm.$emit("duplicate", [10]);
    canvas.vm.$emit("paste", new Event("paste"), { x: 10, y: 20 });
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(2);
    expect(vi.mocked(live.pushEvent).mock.calls.some(([event]) => event === "create_idea")).toBe(
      false,
    );
    expect(wrapper.find("#brainstorming-contributions-closed").exists()).toBe(true);
  });

  it("can remove and restore an existing note while contributions are closed", async () => {
    const current = board();
    const { canvas, live } = workspace((body) => body, {
      session: { ...current.session!, contributions_open: false },
    });
    vi.mocked(live.pushEvent).mockImplementation((event, _payload, callback) => {
      if (event === "delete_idea")
        callback?.({
          status: "ok",
          value: { id: 10, revision: 1, deleted_at: "2026-09-08T10:00:00Z" },
        });
      if (event === "restore_idea") callback?.({ status: "ok", value: idea() });
    });
    canvas.vm.$emit("remove", [10]);
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(1);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(2);
    expect(canvas.props("historyState").canRedo).toBe(true);
  });

  it("closes editing when edit permission is revoked and keeps the unsaved note readable", async () => {
    const { current, canvas, save } = workspace();
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Keep my draft</p>");
    await nextTick();
    expect(canvas.props("editingId")).toBe(10);
    await wrapper.setProps({ board: { ...current, can_edit: false } });
    await vi.advanceTimersByTimeAsync(1_000);
    expect(canvas.props("editingId")).toBeNull();
    expect(canvas.props("permissions").edit).toBe(false);
    expect(canvas.props("notes")[0].body).toBe("<p>Keep my draft</p>");
    expect(canvas.props("historyState").canUndo).toBe(false);
    expect(save).not.toHaveBeenCalled();
  });

  it("discards an invalid text undo so an older note edit can still be undone", async () => {
    const { current, canvas, save } = workspace();
    for (const [id, body] of [
      [10, "<p>First edit</p>"],
      [11, "<p>Second edit</p>"],
    ] as const) {
      canvas.vm.$emit("edit", id);
      canvas.vm.$emit("change", id, body);
      canvas.vm.$emit("finish");
      await flushPromises();
    }
    await wrapper.setProps({
      board: {
        ...current,
        ideas: [
          idea({ body: "<p>First edit</p>", revision: 2 }),
          idea({ id: 11, body: "<p>Changed elsewhere</p>", revision: 3 }),
        ],
      },
    });
    save.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(save).not.toHaveBeenCalled();
    expect(canvas.props("historyState").canUndo).toBe(true);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(save).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ idea_id: 10, body: "<p>Original text</p>" }),
    );
    expect(canvas.props("historyState").canUndo).toBe(false);
  });

  it("undoes and redoes text after the server normalizes quotes, spaces and line breaks", async () => {
    const { canvas, save } = workspace((body) =>
      body.replaceAll('"', "&quot;").replaceAll("&nbsp;", "\u00a0").replaceAll("<br>", "<br/>"),
    );
    const typed = '<p>He said "hi"&nbsp; now<br>next line</p>';
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, typed);
    canvas.vm.$emit("finish");
    await flushPromises();
    expect(canvas.props("notes")[0].body).not.toBe(typed);
    save.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(save).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ idea_id: 10, body: "<p>Original text</p>" }),
    );
    expect(canvas.props("historyState").canRedo).toBe(true);
    canvas.vm.$emit("redo");
    await flushPromises();
    expect(save).toHaveBeenLastCalledWith(expect.objectContaining({ idea_id: 10, body: typed }));
    expect(canvas.props("historyState").canRedo).toBe(false);
  });

  it("turns off canvas cursors while private mode is active", async () => {
    const { current, canvas } = workspace();
    expect(canvas.props("collaboration").cursors).toBe(true);
    await wrapper.setProps({
      board: {
        ...current,
        session: {
          ...current.session!,
          configuration: { ...current.session!.configuration, private_mode: true },
        },
      },
    });
    expect(canvas.props("collaboration").cursors).toBe(false);
  });

  it("retries an interrupted batch without repeating already restored notes", async () => {
    const { canvas, live } = workspace();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const restores: number[] = [];
    let offline = true;
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      const id = Number(payload!.idea_id);
      if (event === "delete_idea") {
        callback?.({
          status: "ok",
          value: { id, revision: 1, deleted_at: "2026-09-08T10:00:00Z" },
        });
      } else if (event === "restore_idea") {
        restores.push(id);
        if (id === 10 && offline) {
          offline = false;
          throw new Error("offline");
        } else callback?.({ status: "ok", value: idea({ id }) });
      }
    });
    canvas.vm.$emit("remove", [10, 11]);
    await flushPromises();
    expect(canvas.props("notes")).toEqual([]);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(restores).toEqual([11, 10]);
    expect(canvas.props("historyState").canUndo).toBe(true);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(restores).toEqual([11, 10, 10]);
    expect(canvas.props("historyState").canUndo).toBe(false);
    expect(canvas.props("historyState").canRedo).toBe(true);
    expect(canvas.props("notes")).toHaveLength(2);
  });
});

describe("workspace round filters", () => {
  it("preserves note drafts and undo when browsing another round and returning", async () => {
    const { current, canvas, live } = workspace((body) => body, { rounds: [round()] });
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Draft before filtering</p>");
    canvas.vm.$emit("finish");
    await flushPromises();
    expect(canvas.props("historyState").canUndo).toBe(true);
    await wrapper.setProps({ board: { ...current, ideas: [], round_filter: 20 } });
    expect(canvas.props("notes")).toHaveLength(0);
    expect(canvas.props("historyState").canUndo).toBe(true);
    await wrapper.setProps({
      board: {
        ...current,
        ideas: [idea({ body: "<p>Draft before filtering</p>", revision: 2 })],
        round_filter: "all",
      },
    });
    expect(canvas.props("notes")[0].body).toBe("<p>Draft before filtering</p>");
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "save_idea",
      expect.objectContaining({ body: "<p>Original text</p>" }),
      expect.any(Function),
    );
  });

  it.each([20, null] as const)(
    "keeps round filter %s during visible text undo and redo, including refreshes",
    async (roundId) => {
      const { canvas, live, save, current } = workspace((body) => body, {
        rounds: [round()],
        round_filter: roundId,
        ideas: [idea({ round_id: roundId })],
      });
      canvas.vm.$emit("edit", 10);
      canvas.vm.$emit("change", 10, "<p>Visible edit</p>");
      canvas.vm.$emit("finish");
      await flushPromises();
      await wrapper.setProps({ board: { ...current, loading: true } });
      save.mockClear();
      canvas.vm.$emit("undo");
      await flushPromises();
      expect(save).toHaveBeenCalledWith(
        expect.objectContaining({ idea_id: 10, body: "<p>Original text</p>" }),
      );
      expect(canvas.props("historyState").canRedo).toBe(true);
      canvas.vm.$emit("redo");
      await flushPromises();
      expect(save).toHaveBeenLastCalledWith(
        expect.objectContaining({ idea_id: 10, body: "<p>Visible edit</p>" }),
      );
      expect(vi.mocked(live.pushEvent).mock.calls.some(([event]) => event === "filter_round")).toBe(
        false,
      );
      expect(canvas.props("notes")).toHaveLength(1);
    },
  );

  it("restores a removed note in the current round without clearing the filter", async () => {
    const { canvas, live } = workspace((body) => body, {
      rounds: [round()],
      round_filter: 20,
      ideas: [idea({ round_id: 20 })],
    });
    const send = vi.mocked(live.pushEvent).getMockImplementation()!;
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (event === "delete_idea")
        callback?.({
          status: "ok",
          value: { id: 10, revision: 1, deleted_at: "2026-09-08T10:00:00Z" },
        });
      else if (event === "restore_idea")
        callback?.({ status: "ok", value: idea({ round_id: 20 }) });
      else send(event, payload, callback);
    });
    canvas.vm.$emit("remove", [10]);
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(0);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(1);
    canvas.vm.$emit("redo");
    await flushPromises();
    expect(canvas.props("notes")).toHaveLength(0);
    expect(vi.mocked(live.pushEvent).mock.calls.some(([event]) => event === "filter_round")).toBe(
      false,
    );
  });

  it("keeps the round filter when undoing a visible multi-note move", async () => {
    const { canvas, live } = workspace((body) => body, {
      rounds: [round()],
      round_filter: 20,
      ideas: [idea({ round_id: 20 }), idea({ id: 11, round_id: 20 })],
    });
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (event === "move_idea")
        callback?.({
          status: "ok",
          value: { x: payload!.x, y: payload!.y, version: Number(payload!.version) + 1 },
        });
    });
    canvas.vm.$emit("move", [
      { id: 10, point: { x: 45, y: 60 } },
      { id: 11, point: { x: 60, y: 75 } },
    ]);
    await flushPromises();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("historyState").canRedo).toBe(true);
    expect(vi.mocked(live.pushEvent).mock.calls.some(([event]) => event === "filter_round")).toBe(
      false,
    );
  });

  it("loads all rounds before undoing a persisted note hidden by the current filter", async () => {
    const { current, canvas, live, save } = workspace((body) => body, { rounds: [round()] });
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Last edit</p>");
    canvas.vm.$emit("finish");
    await flushPromises();
    await wrapper.setProps({ board: { ...current, ideas: [], round_filter: 20 } });
    const send = vi.mocked(live.pushEvent).getMockImplementation()!;
    vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
      if (event === "filter_round") callback?.({ status: "ok" });
      else send(event, payload, callback);
    });
    save.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("historyState").busy).toBe(true);
    expect(canvas.props("historyState").canUndo).toBe(true);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "filter_round",
      expect.objectContaining({ round_id: "all", before_id: 10 }),
      expect.any(Function),
    );
    expect(save).not.toHaveBeenCalled();
    await wrapper.setProps({
      board: { ...current, ideas: [], ideas_next: 50, round_filter: "all", idea_before: null },
    });
    await flushPromises();
    expect(canvas.props("historyState").busy).toBe(true);
    expect(save).not.toHaveBeenCalled();
    await wrapper.setProps({
      board: {
        ...current,
        ideas: [idea({ revision: 2, body: "<p>Last edit</p>" })],
        round_filter: "all",
        idea_before: 10,
      },
    });
    await flushPromises();
    expect(save).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ body: "<p>Original text</p>" }),
    );
    expect(canvas.props("historyState").canUndo).toBe(false);
    expect(canvas.props("historyState").canRedo).toBe(true);
    expect(canvas.props("historyState").busy).toBe(false);
  });

  it("keeps the undo entry when the all-rounds refresh fails and never executes it later", async () => {
    const { current, canvas, live, save } = workspace((body) => body, { rounds: [round()] });
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Last edit</p>");
    canvas.vm.$emit("finish");
    await flushPromises();
    await wrapper.setProps({ board: { ...current, ideas: [], round_filter: 20 } });
    vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) =>
      callback?.({ status: "error", code: "offline" }),
    );
    save.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("historyState").canUndo).toBe(true);
    expect(canvas.props("historyState").busy).toBe(false);
    await wrapper.setProps({
      board: {
        ...current,
        ideas: [idea({ revision: 2, body: "<p>Last edit</p>" })],
        round_filter: "all",
        idea_before: 10,
      },
    });
    await flushPromises();
    expect(save).not.toHaveBeenCalled();
    expect(canvas.props("historyState").canUndo).toBe(true);
  });

  it("cancels pending undo preparation when the board epoch changes", async () => {
    const { current, canvas, live, save } = workspace((body) => body, { rounds: [round()] });
    canvas.vm.$emit("edit", 10);
    canvas.vm.$emit("change", 10, "<p>Last edit</p>");
    canvas.vm.$emit("finish");
    await flushPromises();
    await wrapper.setProps({ board: { ...current, ideas: [], round_filter: 20 } });
    vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) =>
      callback?.({ status: "ok" }),
    );
    save.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("historyState").busy).toBe(true);
    await wrapper.setProps({
      board: { ...current, epoch: "replacement", ideas: [idea()], round_filter: "all" },
    });
    await flushPromises();
    expect(save).not.toHaveBeenCalled();
    const replacement = wrapper.getComponent(Canvas);
    expect(replacement.props("historyState").busy).toBe(false);
    expect(replacement.props("notes")[0].body).toBe("<p>Original text</p>");
  });

  it("creates a new note in the current active round while viewing an older round", async () => {
    const previous = round({ status: "closed", closed_at: "2026-09-08T10:30:00Z" });
    const active = round({ id: 21, number: 2 });
    const { canvas, live } = workspace((body) => body, {
      rounds: [previous, active],
      active_round: active,
      round_filter: 20,
      ideas: [idea({ round_id: 20 })],
    });
    canvas.vm.$emit("add", { x: 20, y: 30 });
    await nextTick();
    expect(live.pushEvent).toHaveBeenCalledWith(
      "filter_round",
      expect.objectContaining({ round_id: "all" }),
      expect.any(Function),
    );
    const created = canvas.props("notes").find((note: Idea) => note.id < 0);
    expect(created?.round_id).toBe(21);
    expect(canvas.props("editingId")).toBe(created.id);
  });

  it("keeps the new note visible if switching to all rounds loses connection", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const active = round({ id: 21, number: 2 });
    const { canvas, live } = workspace((body) => body, {
      rounds: [round(), active],
      active_round: active,
      round_filter: 20,
      ideas: [idea({ round_id: 20 })],
    });
    vi.mocked(live.pushEvent).mockImplementation(() => {
      throw new Error("offline");
    });
    canvas.vm.$emit("add", { x: 20, y: 30 });
    await flushPromises();
    const created = canvas.props("notes").find((note: Idea) => note.id < 0);
    expect(created?.round_id).toBe(21);
    expect(canvas.props("editingId")).toBe(created.id);
  });

  it("duplicates a previous-round note into the current round, preserving its original", async () => {
    const active = round({ id: 21, number: 2 });
    const { canvas, live } = workspace((body) => body, {
      rounds: [round(), active],
      active_round: active,
      round_filter: 20,
      ideas: [idea({ round_id: 20 })],
    });
    canvas.vm.$emit("duplicate", [10]);
    await flushPromises();
    expect(live.pushEvent).toHaveBeenCalledWith(
      "create_idea",
      expect.objectContaining({ round_id: 21, body: "<p>Original text</p>" }),
      expect.any(Function),
    );
    expect(canvas.props("notes").find((note: Idea) => note.id === 10)?.round_id).toBe(20);
  });
});
