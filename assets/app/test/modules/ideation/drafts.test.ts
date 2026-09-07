import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick, ref } from "vue";
import { withSetup, createMockLive } from "../../setup";
import { useIdeaDrafts } from "@modules/ideation/composables/useIdeaDrafts";
import { useBoardConnection } from "@modules/ideation/composables/useBoardConnection";
import type { Reply, Idea, Request } from "@modules/ideation/types";
import { idea, board } from "./fixtures";

const at = () => ({ epoch: "one", session_id: 1 });
afterEach(() => vi.useRealTimers());

function harness() {
  const replies: ((reply: Reply<Idea>) => void)[] = [];
  const send = vi.fn(
    (
      _event: string,
      _payload: Record<string, unknown>,
      _context?: { epoch: string; session_id: number | null },
    ) => new Promise<Reply<Idea>>((resolve) => replies.push(resolve)),
  );
  const { result, app } = withSetup(() => useIdeaDrafts(send as Request, at));
  result.open(idea());
  return { result, app, send, replies };
}

describe("idea drafts", () => {
  it("never replaces new typing with an older save acknowledgement", async () => {
    vi.useFakeTimers();
    const { result, app, send, replies } = harness();
    result.change(10, { body: "<p>First edit</p>" });
    await vi.advanceTimersByTimeAsync(800);
    result.change(10, { body: "<p>Second edit</p>" });
    replies[0]({ status: "ok", value: idea({ body: "<p>First edit</p>", revision: 2 }) });
    await nextTick();
    expect(result.drafts.get(10)?.content.body).toBe("<p>Second edit</p>");
    await vi.advanceTimersByTimeAsync(800);
    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[1]).toEqual([
      "save_idea",
      expect.objectContaining({ revision: 2, body: "<p>Second edit</p>" }),
      at(),
    ]);
    replies[1]({ status: "ok", value: idea({ body: "<p>Second edit</p>", revision: 3 }) });
    await nextTick();
    expect(result.drafts.get(10)?.status).toBe("saved");
    app.unmount();
  });

  it("replays an uncertain request verbatim before sending later edits", async () => {
    vi.useFakeTimers();
    const { result, app, send, replies } = harness();
    result.change(10, { body: "<p>First edit</p>" });
    const saving = result.save(10);
    replies[0]({ status: "error", code: "offline" });
    await saving;
    result.change(10, { body: "<p>Later typing</p>" });
    const retrying = result.save(10);
    expect(send.mock.calls[1]).toEqual(send.mock.calls[0]);
    replies[1]({ status: "ok", value: idea({ body: "<p>First edit</p>", revision: 2 }) });
    await retrying;
    await vi.advanceTimersByTimeAsync(800);
    expect(send.mock.calls[2]).toEqual([
      "save_idea",
      expect.objectContaining({ revision: 2, body: "<p>Later typing</p>" }),
      at(),
    ]);
    app.unmount();
  });

  it("keeps a state-only conflict and saves the chosen text against the current revision", async () => {
    const { result, app, send, replies } = harness();
    result.change(10, { state: "parked" });
    const saving = result.save(10);
    replies[0]({
      status: "conflict",
      value: {
        current: idea({ revision: 2 }),
        receipt: {
          id: 1,
          idea_id: 10,
          base_revision: 1,
          inserted_at: "",
          attempted: { title: "A motive", body: "<p>Original text</p>", state: "parked" },
        },
      },
    });
    await saving;
    expect(result.drafts.get(10)?.status).toBe("conflict");
    result.resolve(10, true);
    expect(send.mock.calls[1]).toEqual([
      "save_idea",
      expect.objectContaining({ revision: 2, state: "parked" }),
      at(),
    ]);
    app.unmount();
  });

  it("quarantines unsaved text on restore and ignores acknowledgements for reused IDs", async () => {
    const { result, app, replies } = harness();
    result.change(10, { body: "<p>Local draft</p>" });
    const saving = result.save(10);
    result.reset();
    result.open(idea({ body: "<p>Restored data</p>" }));
    replies[0]({ status: "ok", value: idea({ body: "<p>Old acknowledgement</p>", revision: 9 }) });
    await saving;
    expect(result.recovered.value).toEqual([
      { title: "A motive", body: "<p>Local draft</p>", state: "active" },
    ]);
    expect(result.drafts.get(10)?.content.body).toBe("<p>Restored data</p>");
    result.reset(false);
    expect(result.recovered.value).toEqual([]);
    app.unmount();
  });

  it("does not regress a saved draft when older board props arrive", () => {
    const { result, app } = harness();
    result.receive(idea({ revision: 3, body: "<p>Third</p>" }));
    result.receive(idea({ revision: 2, body: "<p>Second</p>" }));
    expect(result.drafts.get(10)?.idea.revision).toBe(3);
    app.unmount();
  });
});

it("invalidates transport callbacks after reconnect and removes event listeners", async () => {
  const live = createMockLive();
  const current = ref(board());
  const reset = vi.fn();
  vi.mocked(live.handleEvent).mockReturnValue(5);
  const { result, app } = withSetup(() => useBoardConnection(() => current.value, reset), { live });
  const pending = result.request("inspect_idea", { idea_id: 10 });
  current.value = board({ epoch: "epoch-two" });
  await nextTick();
  vi.mocked(live.pushEvent).mock.calls[0][2]?.({ status: "ok", value: idea() });
  expect(await pending).toEqual({ status: "error", code: "stale_board" });
  expect(reset).toHaveBeenCalledWith("reconnected");
  app.unmount();
  expect(live.removeHandleEvent).toHaveBeenCalledWith(5);
});
