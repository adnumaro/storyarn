import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick, ref, type App } from "vue";
import { withSetup } from "../../setup";
import { useCanvasNotes } from "@modules/ideation/composables/useCanvasNotes";
import type { CreatedIdea, Reply, Request } from "@modules/ideation/types";
import { board, idea, round } from "./fixtures";

const mounted: App[] = [];
function setup() {
  vi.useFakeTimers();
  const current = ref(
    board({
      ideas: [10, 11].map((id) =>
        idea({
          id,
          canvas: {
            x: id * 100,
            y: 20,
            width: 280,
            color: "mint",
            version: 1,
            links: [],
            links_version: 0,
          },
        }),
      ),
    }),
  );
  const replies: ((reply: Reply<unknown>) => void)[] = [];
  const request = vi.fn(
    (_event: string, _payload: Record<string, unknown>, _context?: unknown) =>
      new Promise<Reply<unknown>>((resolve) => replies.push(resolve)),
  );
  const selected = vi.fn();
  const created = vi.fn();
  const { result: notes, app } = withSetup(() =>
    useCanvasNotes(
      () => current.value,
      request as Request,
      () => ({ epoch: current.value.epoch, session_id: current.value.session!.id }),
      selected,
      created,
    ),
  );
  mounted.push(app);
  return { notes, current, request, replies, selected, created };
}
async function flush() {
  for (let i = 0; i < 8; i++) await nextTick();
}
afterEach(() => {
  for (const app of mounted.splice(0)) app.unmount();
  vi.useRealTimers();
});

describe("pending connected note projection", () => {
  it("draws the temporary destination from all sources and removes it on empty cancellation", async () => {
    const { notes, request } = setup();
    const temporary = notes.add({ x: 1400, y: 20 }, "mint", undefined, null, {
      source_ids: [10, 11],
    });
    expect(notes.find(10)?.canvas?.links).toEqual([temporary]);
    expect(notes.find(11)?.canvas?.links).toEqual([temporary]);
    await notes.save(temporary);
    expect(notes.find(temporary)).toBeUndefined();
    expect(notes.find(10)?.canvas?.links).toEqual([]);
    expect(notes.find(11)?.canvas?.links).toEqual([]);
    expect(request).not.toHaveBeenCalled();
  });

  it("restores an unsubmitted note with its sources using a new local identity", async () => {
    const { notes, request } = setup();
    const temporary = notes.add({ x: 1400, y: 20 }, "mint", { body: "<p>Consequence</p>" }, 20, {
      source_ids: [10],
    });
    const removed = await notes.remove(temporary);
    expect(notes.find(10)?.canvas?.links).toEqual([]);
    const restored = await notes.restore(removed!);
    expect(restored).toBeLessThan(0);
    expect(restored).not.toBe(temporary);
    expect(notes.connection(restored!)).toEqual({ source_ids: [10] });
    expect(notes.find(10)?.canvas?.links).toEqual([restored]);
    expect(request).not.toHaveBeenCalled();
  });

  it("replaces a pending arrow with the receipt's persisted destination and notifies history once", async () => {
    const { notes, replies, selected, created } = setup();
    const temporary = notes.add({ x: 1400, y: 20 }, "mint", { body: "<p>Consequence</p>" }, null, {
      source_ids: [10, 11],
    });
    const saving = notes.save(temporary);
    const receipt: CreatedIdea = {
      ...idea({ id: 30, body: "<p>Consequence</p>" }),
      connected_from: [
        { id: 10, before_version: 0, version: 1 },
        { id: 11, before_version: 0, version: 1 },
      ],
    };
    replies[0]({ status: "ok", value: receipt });
    await saving;
    expect(notes.find(10)?.canvas).toMatchObject({ links: [30], links_version: 1 });
    expect(notes.find(11)?.canvas).toMatchObject({ links: [30], links_version: 1 });
    expect(notes.find(temporary)?.id).toBe(30);
    expect(selected).toHaveBeenCalledWith(temporary, 30);
    expect(created).toHaveBeenCalledExactlyOnceWith(receipt);
  });

  it.each(["offline", "unavailable"])(
    "preserves the connected create seed and retry payload after %s",
    async (code) => {
      const { notes, current, request, replies } = setup();
      const ids = [10, 11];
      const temporary = notes.add({ x: 1400, y: 20 }, "blue", { body: "<p>First text</p>" }, 20, {
        source_ids: ids,
      });
      ids.splice(0, ids.length, 999);
      const first = notes.save(temporary);
      const payload = JSON.parse(JSON.stringify(request.mock.calls[0]));
      replies[0]({ status: "error", code });
      await first;
      current.value.active_round = round({ id: 21 });
      notes.change(temporary, "<p>Later typing</p>");
      notes.move(temporary, { x: 1500, y: 40 });
      const retrying = notes.save(temporary);
      expect(request.mock.calls[1]).toEqual(payload);
      expect(request.mock.calls[1][1]).toMatchObject({
        body: "<p>First text</p>",
        round_id: 20,
        connection: { source_ids: [10, 11] },
        canvas: { x: 1400, y: 20, color: "blue" },
      });
      replies[1]({
        status: "ok",
        value: {
          ...idea({ id: 30, body: "<p>First text</p>", round_id: 20 }),
          connected_from: [
            { id: 10, before_version: 0, version: 1 },
            { id: 11, before_version: 0, version: 1 },
          ],
        },
      });
      await retrying;
      expect(notes.find(30)?.body).toBe("<p>Later typing</p>");
      expect(notes.find(30)?.canvas).toMatchObject({ x: 1500, y: 40 });
    },
  );

  it("ignores a creation acknowledgement after the session was replaced", async () => {
    const { notes, current, replies, created, selected } = setup();
    const temporary = notes.add({ x: 1400, y: 20 }, "mint", { body: "<p>Consequence</p>" }, null, {
      source_ids: [10],
    });
    const saving = notes.save(temporary);
    notes.reset(false);
    current.value.epoch = "restored";
    replies[0]({
      status: "ok",
      value: { ...idea({ id: 30 }), connected_from: [{ id: 10, before_version: 0, version: 1 }] },
    });
    await saving;
    expect(notes.find(10)?.canvas?.links).toEqual([]);
    expect(notes.find(30)).toBeUndefined();
    expect(created).not.toHaveBeenCalled();
    expect(selected).not.toHaveBeenCalled();
  });
});

describe("independent connection and movement projections", () => {
  it("keeps an acknowledged link when an older position reply arrives", async () => {
    const { notes, request, replies } = setup();
    notes.move(10, { x: 1400, y: 60 });
    notes.acknowledgeConnections({
      changes: [{ source_id: 10, target_id: 11, connected: true }],
      versions: [{ id: 10, version: 1 }],
    });
    replies[0]({
      status: "ok",
      value: { x: 1400, y: 60, width: 280, version: 2, links: [], links_version: 0 },
    });
    await flush();
    expect(notes.find(10)?.canvas).toMatchObject({
      x: 1400,
      y: 60,
      version: 2,
      links: [11],
      links_version: 1,
    });
    expect(request).toHaveBeenCalledTimes(1);
  });

  it("honors in-place LiveVue updates over both cached position and connection acknowledgements", async () => {
    const { notes, current, replies } = setup();
    notes.acknowledgeConnections({
      changes: [{ source_id: 10, target_id: 11, connected: true }],
      versions: [{ id: 10, version: 1 }],
    });
    notes.move(10, { x: 1400, y: 60 });
    Object.assign(current.value.ideas[0].canvas!, { links: [12], links_version: 3 });
    replies[0]({
      status: "ok",
      value: { x: 1400, y: 60, version: 2, links: [11], links_version: 1 },
    });
    await flush();
    notes.acknowledgeConnections({
      changes: [{ source_id: 10, target_id: 11, connected: true }],
      versions: [{ id: 10, version: 2 }],
    });
    expect(notes.find(10)?.canvas).toMatchObject({ x: 1400, y: 60, links: [12], links_version: 3 });
  });

  it("does not persist a negative preview link in a later connection acknowledgement", async () => {
    const { notes } = setup();
    const temporary = notes.add({ x: 1400, y: 20 }, "mint", undefined, null, { source_ids: [10] });
    notes.acknowledgeConnections({
      changes: [{ source_id: 10, target_id: 11, connected: true }],
      versions: [{ id: 10, version: 1 }],
    });
    expect(notes.find(10)?.canvas?.links).toEqual([11, temporary]);
    await notes.save(temporary);
    expect(notes.find(10)?.canvas?.links).toEqual([11]);
  });
});
