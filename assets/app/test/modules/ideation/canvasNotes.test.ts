import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick, ref } from "vue";
import { withSetup } from "../../setup";
import { useCanvasNotes } from "@modules/ideation/composables/useCanvasNotes";
import type { Reply, Request } from "@modules/ideation/types";
import { idea, board } from "./fixtures";

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
afterEach(() => vi.useRealTimers());

describe("canvas persistence", () => {
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
    await nextTick();
    expect(request.mock.calls[0][0]).toBe("delete_idea");
    expect(request.mock.calls[0][1]).toEqual({ idea_id: 10, revision: 1 });
    expect(result.notes.value[0].state).toBe("active");
    replies[0]({ status: "ok", value: { id: 10 } });
    await removing;
    expect(result.notes.value).toEqual([]);
    app.unmount();
  });
  it("can delete an existing note even after its text was emptied", async () => {
    const { result, app, request, replies } = setup();
    result.open(result.notes.value[0]);
    result.change(10, "<p></p>");
    const removing = result.remove(10);
    expect(request.mock.calls[0][0]).toBe("save_idea");
    replies[0]({ status: "error", code: "validation" });
    await nextTick();
    await nextTick();
    expect(request.mock.calls[1]).toEqual([
      "delete_idea",
      { idea_id: 10, revision: 1 },
      { epoch: "epoch-one", session_id: 1 },
    ]);
    replies[1]({ status: "ok", value: { id: 10 } });
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
