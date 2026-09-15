import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, effectScope, nextTick, reactive, ref } from "vue";
import { flushPromises, mount } from "@vue/test-utils";
import { useCanvasGroups } from "@modules/ideation/composables/useCanvasGroups";
import { useCanvasHistory } from "@modules/ideation/composables/useCanvasHistory";
import CanvasGroup from "@modules/ideation/components/CanvasGroup.vue";
import { groupBounds } from "@modules/ideation/lib/groups";
import type { IdeaGroup, Reply, Request } from "@modules/ideation/types";
import { board, ideaGroup, round } from "./fixtures";

const cleanup: Array<() => void> = [];
afterEach(() => {
  cleanup.splice(0).forEach((fn) => fn());
  vi.restoreAllMocks();
  vi.useRealTimers();
});
function setup(
  overrides: Parameters<typeof board>[0] = {},
  offsets: () => Map<number, number> = () => new Map(),
) {
  const source = ref(board({ groups: [ideaGroup()], ...overrides }));
  const current = source.value;
  const requests: Array<{
    event: string;
    payload: { [key: string]: unknown };
    resolve: (reply: Reply<IdeaGroup>) => void;
  }> = [];
  const request = vi.fn();
  const send: Request = <T>(event: string, payload: { [key: string]: unknown }) => {
    request(event, payload);
    return new Promise<Reply<T>>((resolve) =>
      requests.push({ event, payload, resolve: (reply) => resolve(reply as Reply<T>) }),
    );
  };
  const error = vi.fn();
  const scope = effectScope();
  const result = scope.run(() => {
    const history = useCanvasHistory(error);
    const groups = useCanvasGroups(
      () => source.value,
      send,
      history,
      error,
      vi.fn(),
      async () => true,
      offsets,
    );
    return { history, groups };
  })!;
  cleanup.push(() => scope.stop());
  return { current, source, requests, request, error, ...result };
}
describe("acknowledged group operations", () => {
  it("retains selection and pending writes when full props refresh the same session", async () => {
    const { current, source, groups, history, requests } = setup();
    groups.choose(40);
    const saved = groups.save(40, { title: "Changed" }, 1);
    await flushPromises();
    const result = ideaGroup({ title: "Changed", version: 2 });
    requests[0].resolve({ status: "ok", value: result });
    await flushPromises();
    source.value = { ...current };
    await flushPromises();
    expect(groups.selected.value).toBe(40);
    expect(history.busy.value).toBe(true);
    source.value = { ...source.value, groups: [result] };
    expect(await saved).toBe(true);
    expect(history.canUndo.value).toBe(true);
  });
  it.each(["group", "member"])(
    "rejects a drag when a peer moved its %s after pointer-down",
    async (changed) => {
      const { current, groups, request, error, history } = setup();
      const origin = {
        version: current.groups[0].version,
        member_versions: current.groups[0].members.map((member) => ({
          id: member.idea_id,
          version: member.canvas.version ?? 0,
        })),
      };
      if (changed === "group") {
        current.groups[0].version += 1;
        current.groups[0].canvas.x += 100;
      }
      current.groups[0].members[0].canvas.x! += 100;
      current.groups[0].members[0].canvas.version = origin.member_versions[0].version + 1;
      await groups.move(40, { x: 2, y: -44 }, origin);
      expect(request).not.toHaveBeenCalled();
      expect(error).toHaveBeenCalledWith("stale_group");
      expect(history.canUndo.value).toBe(false);
    },
  );
  it("keeps busy until nested authoritative props contain the saved version", async () => {
    const { current, groups, history, requests } = setup();
    const saved = groups.save(40, { title: "Updated", synthesis: "" }, 1);
    await nextTick();
    expect(requests[0].payload).toMatchObject({ group_id: 40, version: 1, title: "Updated" });
    requests[0].resolve({
      status: "ok",
      value: ideaGroup({ title: "Updated", synthesis: "", version: 2 }),
    });
    await flushPromises();
    expect(history.busy.value).toBe(true);
    current.groups[0].title = "Updated";
    current.groups[0].version = 2;
    await flushPromises();
    expect(await saved).toBe(true);
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(true);
  });
  it("rejects an edit based on an older version before overwriting remote text", async () => {
    const { current, groups, request, error } = setup();
    current.groups[0].version = 2;
    current.groups[0].synthesis = "Someone else's synthesis";
    expect(await groups.save(40, { title: "Mine", synthesis: "My draft" }, 1)).toBe(false);
    expect(request).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledWith("stale_group");
  });
  it("keeps a nonempty synthesis after ungrouping and can undo the exact membership", async () => {
    const { current, groups, history, requests } = setup();
    current.groups[0].synthesis = "Keep this insight";
    const separating = groups.separate(40, { x: 680, y: -44 });
    await flushPromises();
    expect(requests[0]).toMatchObject({
      event: "update_group",
      payload: { idea_ids: [], canvas: { x: 680, y: -44 } },
    });
    const standalone = ideaGroup({
      synthesis: "Keep this insight",
      idea_ids: [],
      members: [],
      version: 2,
      canvas: { ...ideaGroup().canvas, x: 680, y: -44 },
    });
    requests[0].resolve({ status: "ok", value: standalone });
    current.groups = [standalone];
    await separating;
    const undo = history.undo();
    await flushPromises();
    expect(requests[1].payload).toMatchObject({
      idea_ids: [10, 11],
      version: 2,
      canvas: { x: -18, y: -44 },
    });
    const restored = ideaGroup({ synthesis: "Keep this insight", version: 3 });
    requests[1].resolve({ status: "ok", value: restored });
    current.groups = [restored];
    await undo;
    expect(history.canRedo.value).toBe(true);
  });
  it("reuses the request identity for an uncertain offline save", async () => {
    const { groups, requests } = setup();
    const first = groups.save(40, { title: "Retried", synthesis: "" }, 1);
    await flushPromises();
    requests[0].resolve({ status: "error", code: "offline" });
    expect(await first).toBe(false);
    const second = groups.save(40, { title: "Retried", synthesis: "" }, 1);
    await flushPromises();
    expect(requests[1].payload.request_key).toBe(requests[0].payload.request_key);
    requests[1].resolve({ status: "error", code: "offline" });
    await second;
  });
  it("deletes and restores a standalone synthesis without deleting source notes", async () => {
    const { current, groups, history, requests } = setup();
    const standalone = ideaGroup({ idea_ids: [], members: [], synthesis: "Keep this insight" });
    current.groups = [standalone];
    const removing = groups.remove(40);
    await flushPromises();
    expect(requests[0].event).toBe("delete_group");
    const deleted = { ...standalone, version: 2, deleted_at: "2026-09-08T12:00:00Z" };
    requests[0].resolve({ status: "ok", value: deleted });
    current.groups = [];
    await removing;
    expect(current.ideas).toHaveLength(1);
    const undo = history.undo();
    await flushPromises();
    expect(requests[1]).toMatchObject({
      event: "restore_group",
      payload: { version: 2, deleted_at: deleted.deleted_at, idea_ids: [] },
    });
    const restored = { ...standalone, version: 3 };
    requests[1].resolve({ status: "ok", value: restored });
    current.groups = [restored];
    await undo;
    expect(current.groups[0].synthesis).toBe("Keep this insight");
    expect(history.canRedo.value).toBe(true);
  });
  it("undoes multiple edits even though each undo advances the group version", async () => {
    const { current, groups, history, requests } = setup();
    for (const [title, version] of [
      ["Second", 2],
      ["Third", 3],
    ] as const) {
      const saving = groups.save(40, { title }, version - 1);
      await flushPromises();
      const result = ideaGroup({ title, version });
      requests.at(-1)!.resolve({ status: "ok", value: result });
      current.groups = [result];
      await saving;
    }
    for (const [title, version] of [
      ["Second", 4],
      ["Motivations", 5],
    ] as const) {
      const undo = history.undo();
      await flushPromises();
      expect(requests.at(-1)!.payload).toMatchObject({ title, version: version - 1 });
      const result = ideaGroup({ title, version });
      requests.at(-1)!.resolve({ status: "ok", value: result });
      current.groups = [result];
      await undo;
    }
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
  });
  it("treats a late projection as committed, keeps the sync notice and resyncs", async () => {
    vi.useFakeTimers();
    const { current, groups, history, requests, request, error } = setup();
    const first = groups.save(40, { title: "Delayed", synthesis: "" }, 1);
    await nextTick();
    requests[0].resolve({ status: "ok", value: ideaGroup({ title: "Delayed", version: 2 }) });
    await vi.advanceTimersByTimeAsync(12_000);
    expect(await first).toBe(true);
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(true);
    expect(error).toHaveBeenLastCalledWith("group_sync_pending");
    expect(request).toHaveBeenCalledWith("sync_board", {});
    const next = groups.save(40, { title: "Delayed again", synthesis: "" }, 1);
    await nextTick();
    const writes = requests.filter((request) => request.event === "update_group");
    expect(writes[1].payload.request_key).not.toBe(writes[0].payload.request_key);
    writes[1].resolve({ status: "error", code: "offline" });
    await next;
    current.groups[0].title = "Delayed";
    current.groups[0].version = 2;
    await flushPromises();
    expect(error).toHaveBeenLastCalledWith(null, "group_sync_pending");
  });
  it("reports a rejected member placement with group copy", async () => {
    const { groups, requests, error } = setup();
    const moving = groups.move(40, { x: 50, y: -44 });
    await flushPromises();
    expect(requests[0].event).toBe("move_group");
    requests[0].resolve({ status: "error", code: "stale_canvas" });
    await moving;
    expect(error).toHaveBeenCalledWith("stale_group_canvas");
  });
  it("cancels a pending projection wait on navigation and does not add stale history", async () => {
    const { current, groups, history, requests } = setup();
    const saved = groups.save(40, { title: "Changed", synthesis: "" }, 1);
    await flushPromises();
    requests[0].resolve({ status: "ok", value: ideaGroup({ title: "Changed", version: 2 }) });
    await flushPromises();
    current.epoch = "new-epoch";
    await flushPromises();
    expect(await saved).toBe(false);
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(false);
  });
});
function frame(save = vi.fn(async () => false)) {
  const current = reactive(ideaGroup({ synthesis: "Original" }));
  const permissions = reactive({ canEdit: true });
  const Host = defineComponent({
    components: { CanvasGroup },
    setup: () => ({ current, save, groupBounds, permissions }),
    template:
      '<CanvasGroup :group="current" :bounds="groupBounds(current)" :selected="true" :can-edit="permissions.canEdit" :busy="false" :visible-count="2" :zoom="1" :save="save" />',
  });
  const wrapper = mount(Host, { attachTo: document.body });
  cleanup.push(() => wrapper.unmount());
  return { current, wrapper, save, permissions };
}
describe("group text editing", () => {
  it.each(["title", "synthesis"] as const)(
    "keeps IME composition in the %s editor until the text is confirmed",
    async (field) => {
      const { wrapper, save } = frame(vi.fn(async () => true));
      await wrapper
        .get(field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40")
        .trigger("click");
      const input = wrapper.get<HTMLInputElement | HTMLTextAreaElement>(`#group-${field}-40`);
      await input.trigger("compositionstart");
      input.element.value = "物語の動機";
      await input.trigger("input");
      for (const key of ["Enter", "Escape"]) {
        const event = new KeyboardEvent("keydown", {
          key,
          isComposing: true,
          ctrlKey: field === "synthesis",
          bubbles: true,
          cancelable: true,
        });
        input.element.dispatchEvent(event);
        await flushPromises();
        expect(event.defaultPrevented).toBe(false);
        expect(wrapper.get(`#group-${field}-40`).element).toBe(input.element);
        expect(document.activeElement).toBe(input.element);
        expect(input.element.value).toBe("物語の動機");
        expect(save).not.toHaveBeenCalled();
      }
      await input.trigger("compositionend");
      await input.trigger("keydown", { key: "Enter", ctrlKey: field === "synthesis" });
      await flushPromises();
      expect(save).toHaveBeenCalledExactlyOnceWith(40, { [field]: "物語の動機" }, 1);
    },
  );
  it("preserves a synthesis draft and focus across a nested live prop mutation and failed save", async () => {
    const { current, wrapper, save } = frame();
    await wrapper.get("#group-synthesis-add-40").trigger("click");
    const text = wrapper.get<HTMLTextAreaElement>("#group-synthesis-40");
    await text.setValue("My local synthesis");
    text.element.focus();
    current.synthesis = "Collaborator text";
    current.version = 2;
    await nextTick();
    expect(text.element.value).toBe("My local synthesis");
    expect(document.activeElement).toBe(text.element);
    await wrapper.get("#group-synthesis-save-40").trigger("click");
    await flushPromises();
    expect(save).toHaveBeenCalledWith(40, { synthesis: "My local synthesis" }, 1);
    expect(text.element.value).toBe("My local synthesis");
    expect(wrapper.get('[role="alert"]').text()).toContain("Your draft is kept");
    expect(wrapper.get('[role="alert"]').text()).toContain("Collaborator text");
  });
  it.each(["title", "synthesis"] as const)(
    "resets an unchanged %s draft to the latest props before the next edit",
    async (field) => {
      const { current, wrapper, save } = frame();
      const trigger = field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40";
      await wrapper.get(trigger).trigger("click");
      current.title = "Collaborator title";
      current.synthesis = "Collaborator synthesis";
      current.version = 2;
      await nextTick();
      await wrapper
        .get(`#group-${field}-40`)
        .trigger("keydown", { key: "Enter", ctrlKey: field === "synthesis" });
      await flushPromises();
      expect(save).not.toHaveBeenCalled();
      await wrapper.get(trigger).trigger("click");
      const reopened = wrapper.get<HTMLInputElement | HTMLTextAreaElement>(`#group-${field}-40`);
      expect(reopened.element.value).toBe(current[field]);
      await reopened.setValue("My next edit");
      await reopened.trigger("keydown", { key: "Enter", ctrlKey: field === "synthesis" });
      await flushPromises();
      expect(save).toHaveBeenCalledExactlyOnceWith(40, { [field]: "My next edit" }, 2);
    },
  );
  it.each(["title", "synthesis"] as const)(
    "returns focus to the group frame after saving %s",
    async (field) => {
      const { wrapper } = frame(vi.fn(async () => true));
      await wrapper
        .get(field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40")
        .trigger("click");
      const input = wrapper.get(`#group-${field}-40`);
      await input.setValue("Changed text");
      expect(document.activeElement).toBe(input.element);
      const focus = vi.spyOn(wrapper.get("#canvas-group-40").element as HTMLElement, "focus");
      await input.trigger("keydown", { key: "Enter", ctrlKey: field === "synthesis" });
      await flushPromises();
      expect(wrapper.find(`#group-${field}-40`).exists()).toBe(false);
      expect(document.activeElement).toBe(wrapper.get("#canvas-group-40").element);
      expect(focus).toHaveBeenLastCalledWith({ preventScroll: true });
    },
  );
  it.each(["title", "synthesis"] as const)(
    "returns focus to the group frame after cancelling %s",
    async (field) => {
      const { wrapper, save } = frame();
      await wrapper
        .get(field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40")
        .trigger("click");
      const input = wrapper.get(`#group-${field}-40`);
      await input.setValue("Unsubmitted draft");
      await input.trigger("keydown", { key: "Escape" });
      await flushPromises();
      expect(wrapper.find(`#group-${field}-40`).exists()).toBe(false);
      expect(document.activeElement).toBe(wrapper.get("#canvas-group-40").element);
      expect(save).not.toHaveBeenCalled();
    },
  );
  it.each(["title", "synthesis"] as const)(
    "returns focus to the preserved %s draft after a rejected save",
    async (field) => {
      const { wrapper } = frame();
      await wrapper
        .get(field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40")
        .trigger("click");
      const input = wrapper.get<HTMLInputElement | HTMLTextAreaElement>(`#group-${field}-40`);
      await input.setValue("Keep this draft");
      const save = wrapper.get<HTMLButtonElement>(
        field === "title" ? '[aria-label="Save"]' : "#group-synthesis-save-40",
      );
      save.element.focus();
      await save.trigger("click");
      await flushPromises();
      expect(input.element.value).toBe("Keep this draft");
      expect(document.activeElement).toBe(input.element);
    },
  );
  it.each(["title", "synthesis"] as const)(
    "keeps the %s draft selectable after edit access is revoked",
    async (field) => {
      const { wrapper, permissions, save } = frame();
      await wrapper
        .get(field === "title" ? "#group-title-edit-40" : "#group-synthesis-add-40")
        .trigger("click");
      const input = wrapper.get<HTMLInputElement | HTMLTextAreaElement>(`#group-${field}-40`);
      await input.setValue("Copy this draft");
      permissions.canEdit = false;
      await nextTick();
      expect(input.element.readOnly).toBe(true);
      expect(input.element.disabled).toBe(false);
      expect(document.activeElement).toBe(input.element);
      input.element.setSelectionRange(0, 4);
      expect(
        input.element.value.slice(input.element.selectionStart!, input.element.selectionEnd!),
      ).toBe("Copy");
      const button = wrapper.get(
        field === "title" ? '[aria-label="Save"]' : "#group-synthesis-save-40",
      );
      expect(button.attributes("disabled")).toBeDefined();
      await input.trigger("keydown", { key: "Enter", ctrlKey: field === "synthesis" });
      expect(save).not.toHaveBeenCalled();
      expect(input.element.value).toBe("Copy this draft");
    },
  );
  it("leaves caret movement and native undo inside the synthesis editor", async () => {
    const { wrapper } = frame();
    await wrapper.get("#group-synthesis-add-40").trigger("click");
    const listener = vi.fn();
    wrapper.element.parentElement?.addEventListener("keydown", listener);
    const text = wrapper.get("#group-synthesis-40").element;
    for (const key of ["ArrowLeft", "ArrowRight", "z"]) {
      const event = new KeyboardEvent("keydown", {
        key,
        bubbles: true,
        cancelable: true,
        ctrlKey: key === "z",
      });
      text.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(false);
    }
    expect(listener).not.toHaveBeenCalled();
  });
});

describe("groups in a later band", () => {
  const offsets = () =>
    new Map([
      [20, 0],
      [21, 500],
    ]);
  const rounds = [
    round({ id: 20, number: 1, status: "closed" }),
    round({ id: 21, number: 2, status: "active", prompt: null }),
  ];
  const inBand2 = (extra: Partial<IdeaGroup> = {}) =>
    ideaGroup({
      round_id: 21,
      canvas: { x: -18, y: -4, width: 726, height: 382 },
      members: [
        {
          idea_id: 10,
          source_revision: 1,
          round_id: 21,
          canvas: { x: 10, y: 60, width: 280, version: 1 },
        },
        {
          idea_id: 11,
          source_revision: 1,
          round_id: 21,
          canvas: { x: 400, y: 90, width: 280, version: 1 },
        },
      ],
      ...extra,
    });
  it("undoes and redoes a move after earlier bands grow, including while waiting for its reply", async () => {
    const layout = ref(offsets());
    const { source, groups, history, requests } = setup(
      { groups: [inBand2()], rounds },
      () => layout.value,
    );
    expect(groups.groups.value[0].canvas.y).toBe(496);
    const moved = groups.move(40, { x: -18, y: 596 });
    await flushPromises();
    expect(requests[0].payload).toMatchObject({ group_id: 40, version: 1, x: -18, y: 96 });
    layout.value = new Map([[21, 600]]);
    const movedGroup = inBand2({
      version: 2,
      canvas: { x: -18, y: 96, width: 726, height: 382 },
      members: inBand2().members.map((member) => ({
        ...member,
        canvas: { ...member.canvas, y: member.canvas.y! + 100, version: 2 },
      })),
    });
    requests[0].resolve({ status: "ok", value: movedGroup });
    source.value = { ...source.value, groups: [movedGroup] };
    await flushPromises();
    await moved;
    expect(groups.groups.value[0].canvas.y).toBe(696);
    expect(history.canUndo.value).toBe(true);
    layout.value = new Map([[21, 750]]);
    const undo = history.undo();
    await flushPromises();
    expect(requests[1].payload).toMatchObject({ group_id: 40, version: 2, x: -18, y: -4 });
    const restored = inBand2({
      version: 3,
      members: inBand2().members.map((member) => ({
        ...member,
        canvas: { ...member.canvas, version: 3 },
      })),
    });
    requests[1].resolve({ status: "ok", value: restored });
    source.value = { ...source.value, groups: [restored] };
    await flushPromises();
    await undo;
    expect(groups.groups.value[0].canvas.y).toBe(746);
    expect(history.canRedo.value).toBe(true);
    layout.value = new Map([[21, 900]]);
    const redo = history.redo();
    await flushPromises();
    expect(requests[2].payload).toMatchObject({ group_id: 40, version: 3, x: -18, y: 96 });
    const redone = { ...movedGroup, version: 4 };
    requests[2].resolve({ status: "ok", value: redone });
    source.value = { ...source.value, groups: [redone] };
    await redo;
    expect(groups.groups.value[0].canvas.y).toBe(996);
    expect(groups.groups.value[0].members[0].canvas.y).toBe(1060);
  });
  it("restores and detaches a synthesis in its own round after earlier bands grow", async () => {
    const layout = ref(offsets());
    const original = inBand2({ synthesis: "Keep this insight" });
    const { source, groups, history, requests } = setup(
      { groups: [original], rounds },
      () => layout.value,
    );
    const separating = groups.separate(40, { x: 680, y: 800 });
    await flushPromises();
    expect(requests[0].payload).toMatchObject({ idea_ids: [], canvas: { x: 680, y: 300 } });
    const standalone = {
      ...original,
      version: 2,
      idea_ids: [],
      members: [],
      canvas: { ...original.canvas, x: 680, y: 300 },
    };
    requests[0].resolve({ status: "ok", value: standalone });
    source.value = { ...source.value, groups: [standalone] };
    await separating;
    layout.value = new Map([[21, 700]]);
    const undo = history.undo();
    await flushPromises();
    expect(requests[1].payload).toMatchObject({
      idea_ids: [10, 11],
      version: 2,
      canvas: { x: -18, y: -4 },
    });
    const restored = { ...original, version: 3 };
    requests[1].resolve({ status: "ok", value: restored });
    source.value = { ...source.value, groups: [restored] };
    await undo;
    expect(groups.groups.value[0].canvas.y).toBe(696);
    layout.value = new Map([[21, 900]]);
    const redo = history.redo();
    await flushPromises();
    expect(requests[2].payload).toMatchObject({
      idea_ids: [],
      version: 3,
      canvas: { x: 680, y: 300 },
    });
    const redone = { ...standalone, version: 4 };
    requests[2].resolve({ status: "ok", value: redone });
    source.value = { ...source.value, groups: [redone] };
    await redo;
    expect(groups.groups.value[0].canvas.y).toBe(1200);
    expect(groups.groups.value[0].synthesis).toBe("Keep this insight");
  });
  it("still refuses to undo a group move when a collaborator moves a member", async () => {
    const layout = ref(offsets());
    const { source, groups, history, requests, error } = setup(
      { groups: [inBand2()], rounds },
      () => layout.value,
    );
    const moved = groups.move(40, { x: -18, y: 596 });
    await flushPromises();
    const movedGroup = inBand2({ version: 2, canvas: { x: -18, y: 96, width: 726, height: 382 } });
    requests[0].resolve({ status: "ok", value: movedGroup });
    source.value = { ...source.value, groups: [movedGroup] };
    await moved;
    layout.value = new Map([[21, 700]]);
    source.value.groups[0].members[0].canvas.y! += 30;
    source.value.groups[0].members[0].canvas.version = 2;
    await history.undo();
    expect(requests).toHaveLength(1);
    expect(error).toHaveBeenLastCalledWith();
  });
  it("draws a synthesis left on its own in the second band where its notes were", () => {
    const alone = ideaGroup({
      round_id: 21,
      idea_ids: [],
      members: [],
      canvas: { x: -18, y: 100, width: 300, height: 120 },
    });
    const { groups } = setup({ groups: [alone], rounds }, offsets);
    expect(groups.groups.value[0].canvas.y).toBe(600);
  });
});
