import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref } from "vue";
import { useTimerWrites } from "@modules/ideation/composables/useTimerWrites";
import type { SessionTimer } from "@modules/ideation/types";
import { createMockLive } from "../../setup";
import { board, timer } from "./fixtures";

type Reply = (reply: { status: string; code?: string; value?: unknown }) => void;
let wrapper: VueWrapper;
function writes(initial: SessionTimer | null = timer({ status: "running", version: 1 })) {
  const live = createMockLive();
  const session = ref({ ...board().session!, revision: 5 });
  const clock = ref(initial);
  const epoch = ref("a");
  const allowed = ref(true);
  let api!: ReturnType<typeof useTimerWrites>;
  wrapper = mount(
    defineComponent({
      setup() {
        api = useTimerWrites(
          () => session.value,
          () => epoch.value,
          () => clock.value,
          () => allowed.value,
        );
        return () => h("p", String(api.pending.value));
      },
    }),
    { global: { provide: { _live_vue: live } } },
  );
  const call = (index = 0) => {
    const entry = vi.mocked(live.pushEvent).mock.calls[index]!;
    return { event: entry[0], payload: entry[1], reply: entry[2] as Reply };
  };
  return { live, session, clock, epoch, allowed, api, call };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("timer writes", () => {
  it("keeps one write in flight and releases it once the revision and the version have rendered", async () => {
    const { live, session, clock, api, call } = writes();
    api.control("pause_timer", 100);
    api.control("extend_timer", 100);
    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledTimes(1);
    expect(call().event).toBe("pause_timer");
    expect(call().payload).toMatchObject({
      timer_version: 1,
      revision: 5,
      session_id: session.value.id,
      epoch: "a",
    });
    call().reply({ status: "ok", value: { id: session.value.id, revision: 6 } });
    await nextTick();
    // The receipt is ahead of the props: the write waits for both to render.
    expect(api.pending.value).toBe(true);
    session.value = { ...session.value, revision: 6 };
    await nextTick();
    expect(api.pending.value).toBe(true);
    clock.value = timer({ status: "paused", version: 2 });
    await nextTick();
    expect(api.pending.value).toBe(false);
    api.control("resume_timer", 100);
    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledTimes(2);
  });

  it("reports a stale session revision as a stale timer, and a lost push as offline", async () => {
    const { live, api, call } = writes();
    api.control("cancel_timer", 0);
    call().reply({ status: "error", code: "stale_revision" });
    await nextTick();
    expect(api.failure.value).toBe("stale_timer");
    expect(api.pending.value).toBe(false);
    // The transport is down: useLive reports the dropped push through onError.
    vi.spyOn(console, "warn").mockImplementation(() => {});
    vi.mocked(live.pushEvent).mockImplementationOnce(() => {
      throw new Error("down");
    });
    api.control("pause_timer", 100);
    expect(api.failure.value).toBe("offline");
    expect(api.pending.value).toBe(false);
  });

  it("drops a receipt that belongs to another session, an older revision or an earlier board", async () => {
    const { session, epoch, api, call } = writes();
    api.control("pause_timer", 100);
    call().reply({ status: "ok", value: { id: session.value.id + 1, revision: 6 } });
    expect(api.failure.value).toBe("unavailable");
    expect(api.pending.value).toBe(false);
    api.clearFailure();
    api.control("pause_timer", 100);
    call(1).reply({ status: "ok", value: { id: session.value.id, revision: 4 } });
    expect(api.failure.value).toBe("unavailable");
    api.clearFailure();
    api.control("pause_timer", 100);
    epoch.value = "b";
    await nextTick();
    expect(api.pending.value).toBe(false);
    call(2).reply({ status: "error", code: "stale_board" });
    expect(api.failure.value).toBeNull();
  });

  it("only starts an idle clock, only controls a live one, and stops once the actor may not manage", async () => {
    const { live, clock, allowed, api } = writes(null);
    api.control("pause_timer", 100);
    expect(vi.mocked(live.pushEvent)).not.toHaveBeenCalled();
    api.start({ seconds: 90, close_contributions_on_expiry: false });
    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(live.pushEvent).mock.calls[0]![1]).toMatchObject({ seconds: 90, revision: 5 });
    allowed.value = false;
    await nextTick();
    expect(api.pending.value).toBe(false);
    clock.value = timer({ status: "running", version: 3 });
    api.control("pause_timer", 100);
    expect(vi.mocked(live.pushEvent)).toHaveBeenCalledTimes(1);
  });
});
