import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { nextTick } from "vue";
import RoundBar from "@modules/ideation/components/RoundBar.vue";
import { createPromiseMockLive } from "../../setup";
import { board, round, timer } from "./fixtures";
import type { SessionTimer } from "@modules/ideation/types";

let wrapper: VueWrapper;
function bar(
  currentTimer: SessionTimer | null,
  { canManage = true, canEdit = true, single = false } = {},
  send = vi.fn().mockResolvedValue({ status: "ok", value: { id: 1, revision: 2 } }),
) {
  vi.useFakeTimers();
  const current = board();
  wrapper = mount(RoundBar, {
    attachTo: document.body,
    props: {
      round: round({ id: 21, number: 2, status: "active", prompt: "Where does Mara go?" }),
      single,
      last: true,
      canManage,
      pending: false,
      timer: { session: current.session!, epoch: current.epoch, timer: currentTimer, canEdit },
    },
    global: {
      provide: { _live_vue: createPromiseMockLive({}, send) },
      stubs: {
        Popover: { template: "<div><slot /></div>" },
        PopoverTrigger: { template: "<div><slot /></div>" },
        PopoverContent: { template: "<div><slot /></div>" },
      },
    },
  });
  return { send, current };
}
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("timer on the round header", () => {
  it("shows the countdown to everyone and fills the line as time passes", async () => {
    bar(timer(), { canManage: false });
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("05:00");
    expect(wrapper.find("#brainstorming-round-timer-pause").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-timer-start").exists()).toBe(false);
    const fill = wrapper.get("#brainstorming-round-progress-21");
    expect(fill.attributes("style")).toContain("width: 0%");
    vi.advanceTimersByTime(60_000);
    await nextTick();
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("04:00");
    expect(wrapper.get("#brainstorming-round-progress-21").attributes("style")).toContain(
      "width: 20%",
    );
  });

  it("lets the facilitator pause, resume and extend from the header with the rendered version", async () => {
    const { send } = bar(timer({ version: 3 }));
    await wrapper.get("#brainstorming-round-timer-pause").trigger("click");
    expect(send).toHaveBeenLastCalledWith(
      "pause_timer",
      expect.objectContaining({ timer_version: 3, session_id: 1 }),
    );
    await flushPromises();
    await wrapper.setProps({
      round: round({ id: 21, number: 2, status: "active" }),
      timer: {
        session: { ...board().session!, revision: 2 },
        epoch: board().epoch,
        timer: timer({ version: 4, status: "paused", remaining_seconds: 200 }),
        canEdit: true,
      },
    });
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("03:20");
    // The play button says it all; no "Paused" label beside the digits.
    expect(wrapper.text()).not.toContain("Paused");
    expect(wrapper.find('[aria-label="Paused"]').exists()).toBe(false);
    await wrapper.get("#brainstorming-round-timer-resume").trigger("click");
    expect(send).toHaveBeenLastCalledWith(
      "resume_timer",
      expect.objectContaining({ timer_version: 4 }),
    );
    await flushPromises();
    await wrapper.setProps({
      timer: {
        session: { ...board().session!, revision: 3 },
        epoch: board().epoch,
        timer: timer({ version: 5, remaining_seconds: 200, deadline_at: "2026-09-08T10:03:20Z" }),
        canEdit: true,
      },
    });
    await wrapper.get("#brainstorming-round-timer-extend").trigger("click");
    expect(send).toHaveBeenLastCalledWith(
      "extend_timer",
      expect.objectContaining({ timer_version: 5, seconds: 60 }),
    );
  });

  it("offers Start timer while idle and starts with the chosen options", async () => {
    const { send } = bar(null);
    expect(wrapper.find("#brainstorming-round-timer").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-progress-21").exists()).toBe(false);
    await wrapper.get("#brainstorming-round-timer-minutes").setValue("01");
    await wrapper.get("#brainstorming-round-timer-seconds").setValue("30");
    await wrapper.get("#brainstorming-round-timer-start").trigger("click");
    expect(send).toHaveBeenLastCalledWith(
      "start_timer",
      expect.objectContaining({
        seconds: 90,
        close_contributions_on_expiry: false,
      }),
    );
  });

  it("says time is up and fills the whole line, even on a quiet single round", async () => {
    bar(timer({ status: "elapsed", remaining_seconds: 0 }), { canManage: false, single: true });
    await nextTick();
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("00:00");
    expect(wrapper.text()).not.toContain("Time’s up");
    expect(wrapper.find("#brainstorming-round-timer-minutes").exists()).toBe(false);
    expect(wrapper.get("#brainstorming-round-progress-21").attributes("style")).toContain(
      "width: 100%",
    );
    expect(wrapper.text()).not.toContain("Round 2");
  });

  it("shows participants a pause icon instead of a label, and a stopped clock leaves its duration in the digits", async () => {
    bar(timer({ status: "paused", remaining_seconds: 200 }), { canManage: false });
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("03:20");
    expect(wrapper.text()).not.toContain("Paused");
    expect(wrapper.find('[aria-label="Paused"]').exists()).toBe(true);
    wrapper.unmount();
    bar(timer({ version: 5, status: "cancelled", duration_seconds: 960, remaining_seconds: 0 }));
    expect(
      (wrapper.get("#brainstorming-round-timer-minutes").element as HTMLInputElement).value,
    ).toBe("16");
    expect(
      (wrapper.get("#brainstorming-round-timer-seconds").element as HTMLInputElement).value,
    ).toBe("00");
  });

  it("lets the facilitator cancel a running timer and start again once it is up", async () => {
    const { send } = bar(timer({ version: 7 }));
    await wrapper.get("#brainstorming-round-timer-cancel").trigger("click");
    expect(send).toHaveBeenLastCalledWith(
      "cancel_timer",
      expect.objectContaining({ timer_version: 7 }),
    );
    await flushPromises();
    await wrapper.setProps({
      timer: {
        session: { ...board().session!, revision: 2 },
        epoch: board().epoch,
        timer: timer({ version: 8, status: "elapsed", remaining_seconds: 0 }),
        canEdit: true,
      },
    });
    await flushPromises();
    const minutes = wrapper.get("#brainstorming-round-timer-minutes");
    expect((minutes.element as HTMLInputElement).value).toBe("00");
    await minutes.setValue("05");
    await wrapper.get("#brainstorming-round-timer-start").trigger("click");
    expect(send).toHaveBeenLastCalledWith("start_timer", expect.objectContaining({ seconds: 300 }));
  });
});
