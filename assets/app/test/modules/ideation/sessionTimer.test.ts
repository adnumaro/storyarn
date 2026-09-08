import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref } from "vue";
import { useSessionTimer } from "@modules/ideation/composables/useSessionTimer";
import type { SessionTimer } from "@modules/ideation/types";
import { timer } from "./fixtures";

let wrapper: VueWrapper;
function clock(initial: SessionTimer | null = timer()) {
  vi.useFakeTimers();
  const current = ref(initial);
  const context = ref("epoch:session");
  const expired = vi.fn();
  wrapper = mount(
    defineComponent({
      setup() {
        const countdown = useSessionTimer(
          () => current.value,
          () => context.value,
          expired,
        );
        return () => h("p", countdown.display.value);
      },
    }),
  );
  return { current, context, expired };
}
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
});

describe("shared session timer clock", () => {
  it("uses the server deadline and monotonic time despite a skewed or changing wall clock", async () => {
    clock();
    vi.setSystemTime(new Date("2099-01-01T00:00:00Z"));
    expect(wrapper.text()).toBe("5:00");
    await vi.advanceTimersByTimeAsync(62_000);
    expect(wrapper.text()).toBe("3:58");
    vi.setSystemTime(new Date("2000-01-01T00:00:00Z"));
    await vi.advanceTimersByTimeAsync(1_000);
    expect(wrapper.text()).toBe("3:57");
  });
  it("requests one sync at expiry, including repeated stale refreshes, and rearms after extension", async () => {
    const { current, expired } = clock(timer({ deadline_at: "2026-09-08T10:00:02Z" }));
    await vi.advanceTimersByTimeAsync(2_000);
    expect(wrapper.text()).toBe("0:00");
    expect(expired).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(30_000);
    current.value = { ...current.value!, server_now: "2026-09-08T10:00:30Z" };
    await nextTick();
    expect(expired).toHaveBeenCalledTimes(1);
    current.value = { ...current.value!, version: 2, deadline_at: "2026-09-08T10:00:32Z" };
    await nextTick();
    expect(wrapper.text()).toBe("0:02");
    await vi.advanceTimersByTimeAsync(2_000);
    expect(expired).toHaveBeenCalledTimes(2);
  });
  it("keeps paused remaining seconds unchanged and recalibrates on resume", async () => {
    const { current, expired } = clock(
      timer({ status: "paused", deadline_at: null, remaining_seconds: 3 }),
    );
    await vi.advanceTimersByTimeAsync(60_000);
    expect(wrapper.text()).toBe("0:03");
    expect(expired).not.toHaveBeenCalled();
    current.value = timer({ version: 2, deadline_at: "2026-09-08T10:00:03Z" });
    await nextTick();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(wrapper.text()).toBe("0:02");
  });
  it("stops the interval on cancellation and releases it on unmount", async () => {
    const { current, expired } = clock();
    expect(vi.getTimerCount()).toBe(1);
    current.value = timer({ status: "cancelled" });
    await nextTick();
    expect(vi.getTimerCount()).toBe(0);
    expect(expired).not.toHaveBeenCalled();
    current.value = timer({ version: 2 });
    await nextTick();
    expect(vi.getTimerCount()).toBe(1);
    wrapper.unmount();
    expect(vi.getTimerCount()).toBe(0);
  });
});
