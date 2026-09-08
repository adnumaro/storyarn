import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick, ref } from "vue";
import { withSetup } from "../../setup";
import { useCanvasNotes } from "@modules/ideation/composables/useCanvasNotes";
import type { Reply, Request } from "@modules/ideation/types";
import { idea, board, round } from "./fixtures";

function setup() {
  vi.useFakeTimers();
  const current = ref(board());
  const replies: ((reply: Reply<unknown>) => void)[] = [];
  const request = vi.fn(
    (_event: string, _payload: Record<string, unknown>) =>
      new Promise<Reply<unknown>>((resolve) => replies.push(resolve)),
  );
  const selected = vi.fn();
  const { result, app } = withSetup(() =>
    useCanvasNotes(
      () => current.value,
      request as Request,
      () => ({ epoch: current.value.epoch, session_id: 1 }),
      selected,
    ),
  );
  return { result, app, current, request, replies, selected };
}
async function flush() {
  for (let i = 0; i < 6; i++) await nextTick();
}
const deletedAt = "2026-09-07T12:00:00Z";
const deletion = { id: 10, revision: 1, deleted_at: deletedAt };
afterEach(() => vi.useRealTimers());

describe("canvas persistence", () => {
  it("pauses pending autosaves after becoming a viewer without discarding local text", async () => {
    const { result, app, current, request } = setup();
    result.open(result.notes.value[0]);
    result.change(10, "<p>Unsaved existing text</p>");
    const id = result.add({ x: 40, y: 60 });
    result.change(id, "<p>Unsaved new note</p>");
    current.value = { ...current.value, can_edit: false };
    await nextTick();
    await vi.advanceTimersByTimeAsync(1_000);
    result.retry(10);
    result.retry(id);
    expect(request).not.toHaveBeenCalled();
    expect(result.find(10)?.body).toBe("<p>Unsaved existing text</p>");
    expect(result.find(id)?.body).toBe("<p>Unsaved new note</p>");
    expect(result.drafts.drafts.get(10)?.status).toBe("unsaved");
    current.value = { ...current.value, can_edit: true };
    await nextTick();
    result.retry(10);
    expect(request.mock.calls[0]).toEqual([
      "save_idea",
      expect.objectContaining({ idea_id: 10, body: "<p>Unsaved existing text</p>" }),
      expect.anything(),
    ]);
    app.unmount();
  });
  it("replays an uncertain creation unchanged and retains subsequent typing", async () => {
    const { result, app, request, replies, selected } = setup();
    const id = result.add({ x: 40, y: 60 });
    result.change(id, "<p>First</p>");
    const save = result.save(id);
    replies[0]({ status: "error", code: "offline" });
    await save;
    result.change(id, "<p>Later typing</p>");
    const retry = result.save(id);
    expect(request.mock.calls[1]).toEqual(request.mock.calls[0]);
    replies[1]({ status: "ok", value: idea({ id: 11, body: "<p>First</p>" }) });
    await retry;
    expect(selected).toHaveBeenCalledWith(id, 11);
    expect(result.notes.value.find((n) => n.id === 11)?.body).toBe("<p>Later typing</p>");
    await vi.advanceTimersByTimeAsync(800);
    expect(request.mock.calls[2][0]).toBe("save_idea");
    expect(request.mock.calls[2][1]).toMatchObject({
      idea_id: 11,
      body: "<p>Later typing</p>",
      revision: 1,
    });
    app.unmount();
  });
  it("coalesces moves against their own version and retries an uncertain move verbatim", async () => {
    const { result, app, request, replies } = setup();
    result.move(10, { x: 40, y: 60 });
    result.move(10, { x: 90, y: 110 });
    expect(request).toHaveBeenCalledTimes(1);
    replies[0]({ status: "error", code: "offline" });
    await nextTick();
    result.retry(10);
    expect(request.mock.calls[1]).toEqual(request.mock.calls[0]);
    replies[1]({ status: "ok", value: { x: 40, y: 60, version: 1 } });
    await nextTick();
    expect(request.mock.calls[2][1]).toMatchObject({ x: 90, y: 110, version: 1 });
    replies[2]({ status: "ok", value: { x: 90, y: 110, version: 2 } });
    await nextTick();
    expect(result.notes.value[0].canvas).toMatchObject({ x: 90, y: 110, version: 2 });
    app.unmount();
  });
  it("deletes through a distinct command without changing creative state", async () => {
    const { result, app, request, replies } = setup();
    const removing = result.remove(10);
    await flush();
    expect(request.mock.calls[0][0]).toBe("delete_idea");
    expect(request.mock.calls[0][1]).toEqual({ idea_id: 10, revision: 1 });
    expect(result.notes.value[0].state).toBe("active");
    replies[0]({ status: "ok", value: deletion });
    await removing;
    expect(result.notes.value).toEqual([]);
    app.unmount();
  });
  it("can delete an existing note even after its text was emptied", async () => {
    const { result, app, request, replies } = setup();
    result.open(result.notes.value[0]);
    result.change(10, "<p></p>");
    const removing = result.remove(10);
    await flush();
    expect(request.mock.calls[0][0]).toBe("save_idea");
    replies[0]({ status: "error", code: "validation" });
    await flush();
    expect(request.mock.calls[1]).toEqual([
      "delete_idea",
      { idea_id: 10, revision: 1 },
      { epoch: "epoch-one", session_id: 1 },
    ]);
    replies[1]({ status: "ok", value: deletion });
    await removing;
    expect(result.notes.value).toEqual([]);
    result.reset();
    expect(result.drafts.recovered.value).toEqual([]);
    app.unmount();
  });
  it("cancels only unsubmitted empty notes and isolates late acknowledgements after restore", async () => {
    const { result, app, replies, selected } = setup();
    const blank = result.add({ x: 0, y: 0 });
    await result.save(blank);
    expect(result.newNotes.size).toBe(0);
    const id = result.add({ x: 40, y: 60 });
    result.change(id, "<p>Keep this text</p>");
    const saving = result.save(id);
    result.reset();
    replies[0]({ status: "ok", value: idea({ id: 11 }) });
    await saving;
    expect(result.drafts.recovered.value[0].body).toBe("<p>Keep this text</p>");
    expect(selected).not.toHaveBeenCalled();
    expect(result.notes.value.some((n) => n.id === 11)).toBe(false);
    result.reset(false);
    expect(result.drafts.recovered.value).toEqual([]);
    app.unmount();
  });
});

describe("canvas acknowledged undo primitives", () => {
  it("keeps the same render key and resolves temporary references after first save", async () => {
    const { result, app, replies } = setup();
    const local = result.add({ x: 12, y: 34 }, "mint", { body: "<p>New note</p>" });
    const key = result.key(local);
    const saving = result.save(local);
    replies[0]({ status: "ok", value: idea({ id: 44, body: "<p>New note</p>" }) });
    await saving;
    expect(result.key(44)).toBe(key);
    expect(result.key(local)).toBe(key);
    expect(result.resolveId(local)).toBe(44);
    expect(result.find(local)?.id).toBe(44);
    app.unmount();
  });
  it("restores the same deleted ID using its exact deletion revision and timestamp", async () => {
    const { result, app, request, replies } = setup();
    const removing = result.remove(10);
    await flush();
    replies[0]({ status: "ok", value: deletion });
    const removed = await removing;
    expect(removed).toMatchObject({
      ...deletion,
      idea: { id: 10, body: "<p>Original text</p>", state: "active" },
    });
    expect(result.find(10)).toBeUndefined();
    const restoring = result.restore(removed!);
    expect(request.mock.calls[1]).toEqual([
      "restore_idea",
      { idea_id: 10, revision: 1, deleted_at: deletedAt },
    ]);
    replies[1]({ status: "ok", value: idea({ id: 10, revision: 2, deleted_at: null }) });
    expect(await restoring).toBe(10);
    expect(result.find(10)).toMatchObject({
      id: 10,
      revision: 2,
      state: "active",
      deleted_at: null,
    });
    const deletingAgain = result.remove(10);
    await flush();
    expect(request.mock.calls[2][1]).toEqual({ idea_id: 10, revision: 2 });
    replies[2]({
      status: "ok",
      value: { ...deletion, revision: 2, deleted_at: "2026-09-07T12:01:00Z" },
    });
    await deletingAgain;
    app.unmount();
  });
  it("undoes deleting an unsaved local note without inventing a server deletion", async () => {
    const { result, app, request, replies } = setup();
    const local = result.add({ x: 70, y: 90 }, "blue", {
      body: "<p>Not submitted</p>",
      state: "parked",
    });
    const removed = await result.remove(local);
    expect(removed).toMatchObject({ id: local, revision: 0, deleted_at: null });
    expect(result.find(local)).toBeUndefined();
    expect(request).not.toHaveBeenCalled();
    const restored = await result.restore(removed!);
    expect(restored).toBeLessThan(0);
    expect(restored).not.toBe(local);
    expect(result.resolveId(local)).toBe(restored);
    expect(result.find(local)).toMatchObject({
      body: "<p>Not submitted</p>",
      state: "parked",
      canvas: { x: 70, y: 90, color: "blue" },
    });
    const saving = result.save(local);
    replies[0]({
      status: "ok",
      value: idea({ id: 50, body: "<p>Not submitted</p>", state: "parked" }),
    });
    await saving;
    expect(result.resolveId(local)).toBe(50);
    expect(result.resolveId(restored!)).toBe(50);
    app.unmount();
  });
  it("waits for every coalesced move before deleting and snapshots the latest placement", async () => {
    const { result, app, request, replies } = setup();
    result.move(10, { x: 80, y: 90 });
    result.move(10, { x: 110, y: 120 });
    const removing = result.remove(10);
    await flush();
    expect(request.mock.calls.map(([event]) => event)).toEqual(["move_idea"]);
    replies[0]({ status: "ok", value: { x: 80, y: 90, version: 1 } });
    await flush();
    expect(request.mock.calls.map(([event]) => event)).toEqual(["move_idea", "move_idea"]);
    replies[1]({ status: "ok", value: { x: 110, y: 120, version: 2 } });
    await flush();
    expect(request.mock.calls[2][0]).toBe("delete_idea");
    replies[2]({ status: "ok", value: deletion });
    expect(await removing).toMatchObject({ idea: { canvas: { x: 110, y: 120, version: 2 } } });
    app.unmount();
  });
  it("settles a note only after pending placement and text writes are acknowledged", async () => {
    const { result, app, request, replies } = setup();
    result.open(result.find(10)!);
    result.change(10, "<p>Updated text</p>");
    result.move(10, { x: 40, y: 80 });
    let finished = false;
    const settling = result.settle(10).then((value) => {
      finished = true;
      return value;
    });
    await flush();
    expect(finished).toBe(false);
    expect(request.mock.calls[0][0]).toBe("move_idea");
    replies[0]({ status: "ok", value: { x: 40, y: 80, version: 1 } });
    await flush();
    expect(request.mock.calls[1][0]).toBe("save_idea");
    expect(finished).toBe(false);
    replies[1]({ status: "ok", value: idea({ revision: 2, body: "<p>Updated text</p>" }) });
    expect(await settling).toBe(true);
    expect(result.find(10)?.body).toBe("<p>Updated text</p>");
    app.unmount();
  });
  it("rejects stale pending deletion and restoration replies after an epoch reset", async () => {
    const { result, app, replies, current } = setup();
    const removing = result.remove(10);
    await flush();
    replies[0]({ status: "ok", value: deletion });
    const removed = await removing;
    const restoring = result.restore(removed!);
    current.value = board({ epoch: "new-epoch", ideas: [] });
    result.reset(false);
    replies[1]({ status: "ok", value: idea({ revision: 2 }) });
    expect(await restoring).toBeNull();
    expect(result.notes.value).toEqual([]);
    expect(result.drafts.drafts.size).toBe(0);
    expect(result.drafts.recovered.value).toEqual([]);
    app.unmount();
  });
  it("allows content operations after a definitively rejected placement", async () => {
    const { result, app, replies } = setup();
    result.move(10, { x: 40, y: 80 });
    replies[0]({ status: "error", code: "stale_canvas" });
    await flush();
    expect(result.find(10)?.canvas?.x).not.toBe(40);
    expect(await result.settle(10)).toBe(true);
    app.unmount();
  });
  it("does not settle an uncertain placement before its exact retry is reconciled", async () => {
    const { result, app, replies } = setup();
    result.move(10, { x: 40, y: 80 });
    replies[0]({ status: "error", code: "offline" });
    await flush();
    expect(await result.settle(10)).toBe(false);
    result.retry(10);
    replies[1]({ status: "ok", value: { x: 40, y: 80, version: 1 } });
    await flush();
    expect(await result.settle(10)).toBe(true);
    app.unmount();
  });
  it("releases operations waiting on a pending move when reset invalidates their session", async () => {
    const { result, app, replies, current, request } = setup();
    result.move(10, { x: 40, y: 80 });
    const removing = result.remove(10);
    const settling = result.settle(10);
    current.value = board({ epoch: "new-epoch", ideas: [] });
    result.reset(false);
    await flush();
    expect(await removing).toBeNull();
    expect(await settling).toBe(false);
    replies[0]({ status: "ok", value: { x: 40, y: 80, version: 1 } });
    await flush();
    expect(request).toHaveBeenCalledTimes(1);
    expect(result.notes.value).toEqual([]);
    app.unmount();
  });
  it("never recovers deleted local or persisted buffers when resetting", async () => {
    const { result, app, replies } = setup();
    const local = result.add({ x: 40, y: 80 }, "mint", { body: "<p>Delete me</p>" });
    await result.remove(local);
    result.open(result.find(10)!);
    result.change(10, "<p></p>");
    const removing = result.remove(10);
    await flush();
    replies[0]({ status: "error", code: "validation" });
    await flush();
    replies[1]({ status: "ok", value: deletion });
    await removing;
    result.reset();
    expect(result.drafts.recovered.value).toEqual([]);
    expect(result.newNotes.size).toBe(0);
    app.unmount();
  });
});

describe("round contribution provenance", () => {
  it("keeps the round where writing began when the first save happens after another round starts", async () => {
    const { result, app, current, request, replies } = setup();
    current.value = { ...current.value, active_round: round() };
    const local = result.add({ x: 10, y: 20 });
    result.change(local, "<p>Started in round one</p>");
    current.value = { ...current.value, active_round: round({ id: 21, number: 2 }) };
    const saving = result.save(local);
    expect(request.mock.calls[0][1]).toMatchObject({ round_id: 20 });
    replies[0]({ status: "ok", value: idea({ id: 44, round_id: 20, late_contribution: true }) });
    await saving;
    expect(result.find(local)).toMatchObject({ round_id: 20, late_contribution: true });
    app.unmount();
  });

  it("retries uncertain creation with the same round and content after the active round changes", async () => {
    const { result, app, current, request, replies } = setup();
    current.value = { ...current.value, active_round: round() };
    const local = result.add({ x: 10, y: 20 }, "mint", { body: "<p>Initial</p>" });
    const saving = result.save(local);
    replies[0]({ status: "error", code: "offline" });
    await saving;
    current.value = { ...current.value, active_round: round({ id: 21, number: 2 }) };
    result.change(local, "<p>More text</p>");
    const retry = result.save(local);
    expect(request.mock.calls[1]).toEqual(request.mock.calls[0]);
    expect(request.mock.calls[1][1]).toMatchObject({ round_id: 20, body: "<p>Initial</p>" });
    replies[1]({ status: "ok", value: idea({ id: 44, body: "<p>Initial</p>", round_id: 20 }) });
    await retry;
    expect(result.find(local)).toMatchObject({ body: "<p>More text</p>", round_id: 20 });
    app.unmount();
  });

  it("keeps notes begun without a round unassigned when a round starts before autosave", async () => {
    const { result, app, current, request, replies } = setup();
    const local = result.add({ x: 10, y: 20 }, "mint", { body: "<p>Open exploration</p>" });
    current.value = { ...current.value, active_round: round() };
    const saving = result.save(local);
    expect(request.mock.calls[0][1]).toMatchObject({ round_id: null });
    replies[0]({ status: "ok", value: idea({ id: 44 }) });
    await saving;
    app.unmount();
  });

  it("restores a locally deleted note to its original round while a copy starts in the current round", async () => {
    const { result, app, current } = setup();
    current.value = { ...current.value, active_round: round() };
    const local = result.add({ x: 10, y: 20 }, "mint", { body: "<p>Keep provenance</p>" });
    const deletion = await result.remove(local);
    current.value = { ...current.value, active_round: round({ id: 21, number: 2 }) };
    const restored = await result.restore(deletion!);
    expect(result.find(restored!)?.round_id).toBe(20);
    const copy = result.add({ x: 40, y: 50 }, "mint", deletion!.idea);
    expect(result.find(copy)?.round_id).toBe(21);
    app.unmount();
  });

  it("preserves unsaved text and unfinished notes while filtering through previous rounds", async () => {
    const { result, app, current } = setup();
    result.open(result.find(10)!);
    result.change(10, "<p>Draft kept</p>");
    const local = result.add({ x: 40, y: 50 }, "mint", { body: "<p>Unsubmitted note</p>" });
    current.value = { ...current.value, ideas: [], round_filter: 20, active_round: round() };
    await nextTick();
    expect(result.drafts.drafts.get(10)?.content.body).toBe("<p>Draft kept</p>");
    expect(result.newNotes.get(local)?.idea).toMatchObject({
      body: "<p>Unsubmitted note</p>",
      round_id: null,
    });
    current.value = { ...current.value, ideas: [idea()], round_filter: "all" };
    await nextTick();
    expect(result.find(10)?.body).toBe("<p>Draft kept</p>");
    app.unmount();
  });
});

describe("closed contributions and pending drafts", () => {
  it("resolves an uncertain creation using its original request after contributions close", async () => {
    const { result, app, current, request, replies } = setup();
    const local = result.add({ x: 10, y: 20 }, "mint", { body: "<p>May already be saved</p>" });
    const saving = result.save(local);
    replies[0]({ status: "error", code: "offline" });
    await saving;
    current.value = {
      ...current.value,
      session: { ...current.value.session!, contributions_open: false },
    };
    const retry = result.save(local);
    expect(request.mock.calls[1]).toEqual(request.mock.calls[0]);
    replies[1]({ status: "ok", value: idea({ id: 44, body: "<p>May already be saved</p>" }) });
    await retry;
    expect(result.find(local)?.id).toBe(44);
    app.unmount();
  });
  it("keeps a rejected unfinished draft and can restore it locally while new contributions are closed", async () => {
    const { result, app, current, replies } = setup();
    const local = result.add({ x: 10, y: 20 }, "mint", {
      body: "<p>Keep this unfinished idea</p>",
    });
    current.value = {
      ...current.value,
      session: { ...current.value.session!, contributions_open: false },
    };
    const saving = result.save(local);
    replies[0]({ status: "error", code: "contributions_closed" });
    await saving;
    expect(result.find(local)?.body).toBe("<p>Keep this unfinished idea</p>");
    expect(result.errors.get(local)).toBe("contributions_closed");
    const removed = await result.remove(local);
    const restored = await result.restore(removed!);
    expect(result.find(restored!)?.body).toBe("<p>Keep this unfinished idea</p>");
    app.unmount();
  });
});
