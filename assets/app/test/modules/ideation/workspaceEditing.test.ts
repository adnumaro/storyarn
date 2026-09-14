import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, nextTick } from "vue";
import BrainstormingWorkspace from "@modules/ideation/BrainstormingWorkspace.vue";
import { createMockLive } from "../../setup";
import { board, idea } from "./fixtures";
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

  it("turns off canvas cursors while the round in progress is private", async () => {
    const { current, canvas } = workspace();
    expect(canvas.props("collaboration").cursors).toBe(true);
    await wrapper.setProps({
      board: { ...current, active_round: { ...current.active_round!, private: true } },
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
