import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { nextTick, reactive } from "vue";
import TimerControls from "@modules/ideation/TimerControls.vue";
import { Popover } from "@components/ui/popover";
import { createPromiseMockLive } from "../../setup";
import { board, timer } from "./fixtures";
import type { SessionTimer } from "@modules/ideation/types";

let wrapper: VueWrapper;
function controls(
  currentTimer: SessionTimer | null = null,
  send = vi.fn().mockResolvedValue({ status: "ok", value: { id: 1, revision: 2 } }),
  manage = true,
) {
  vi.useFakeTimers();
  const current = board();
  wrapper = mount(TimerControls, {
    attachTo: document.body,
    props: {
      session: current.session!,
      epoch: current.epoch,
      timer: currentTimer,
      canManage: manage,
      canEdit: true,
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

describe("session timer controls", () => {
  it("preserves keyboard focus on the same control when pause becomes resume", async () => {
    const { current, send } = controls(
      timer(),
      vi.fn().mockResolvedValue({ status: "ok", value: { id: 1, revision: 2 } }),
    );
    const pause = wrapper.get("#brainstorming-timer-pause").element as HTMLButtonElement;
    pause.focus();
    expect(document.activeElement).toBe(pause);
    await wrapper.get("#brainstorming-timer-pause").trigger("click");
    await flushPromises();
    expect(pause.disabled).toBe(false);
    expect(pause.getAttribute("aria-disabled")).toBe("true");
    expect(document.activeElement).toBe(pause);
    await wrapper.get("#brainstorming-timer-pause").trigger("click");
    expect(send).toHaveBeenCalledTimes(1);
    await wrapper.setProps({
      session: { ...current.session!, revision: 2 },
      timer: timer({ status: "paused", version: 2, deadline_at: null }),
    });
    expect(wrapper.get("#brainstorming-timer-resume").element).toBe(pause);
    expect(document.activeElement).toBe(pause);
    expect(pause.getAttribute("aria-disabled")).toBe("false");
    send.mockResolvedValue({ status: "ok", value: { id: 1, revision: 3 } });
    await wrapper.get("#brainstorming-timer-resume").trigger("click");
    await wrapper.setProps({
      session: { ...current.session!, revision: 3 },
      timer: timer({ version: 3 }),
    });
    expect(wrapper.get("#brainstorming-timer-pause").element).toBe(pause);
    expect(document.activeElement).toBe(pause);
  });
  it("waits for the write reply when refreshed props arrive first", async () => {
    let finish!: (reply: { status: string; value: { id: number; revision: number } }) => void;
    const { current, send } = controls(
      timer(),
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await wrapper.setProps({
      session: { ...current.session!, revision: 2 },
      timer: timer({ version: 2, duration_seconds: 360 }),
    });
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    expect(send).toHaveBeenCalledTimes(1);
    finish({ status: "ok", value: { id: 1, revision: 2 } });
    await flushPromises();
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeUndefined();
  });
  it.each(["timer", "session"])(
    "observes in-place updates when %s changes first",
    async (first) => {
      const { current } = controls(timer());
      const session = reactive(current.session!);
      const clock = reactive(timer());
      await wrapper.setProps({ session, timer: clock });
      await wrapper.get("#brainstorming-timer-extend").trigger("click");
      await flushPromises();
      if (first === "timer") clock.version = 2;
      else session.revision = 2;
      await nextTick();
      expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
      if (first === "timer") session.revision = 2;
      else clock.version = 2;
      await nextTick();
      expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeUndefined();
    },
  );
  it("keeps a newly started timer pending until its first rendered version arrives", async () => {
    const { current, send } = controls();
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    await wrapper.setProps({ session: { ...current.session!, revision: 2 } });
    expect(wrapper.get("#brainstorming-timer-start").attributes("disabled")).toBeDefined();
    await wrapper.get("form").trigger("submit");
    expect(send).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ timer: timer() });
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeUndefined();
  });
  it("releases contribution no-ops at the acknowledged revision without waiting for a timer", async () => {
    controls(null, vi.fn().mockResolvedValue({ status: "ok", value: { id: 1, revision: 1 } }));
    await wrapper.get("#brainstorming-contributions-toggle").trigger("click");
    await flushPromises();
    expect(
      wrapper.get("#brainstorming-contributions-toggle").attributes("disabled"),
    ).toBeUndefined();
  });
  it("waits for the acknowledged session and timer before allowing another extension", async () => {
    const { current, send } = controls(
      timer(),
      vi.fn().mockResolvedValue({ status: "ok", value: { id: 1, revision: 2 } }),
    );
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await flushPromises();
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    expect(send).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ session: { ...current.session!, revision: 2 } });
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
    await wrapper.setProps({ timer: timer({ version: 2, duration_seconds: 360 }) });
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeUndefined();
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    expect(send).toHaveBeenLastCalledWith("extend_timer", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 2,
      timer_version: 2,
      seconds: 60,
    });
  });
  it("starts with the chosen duration and notification-only defaults", async () => {
    const { send } = controls();
    await wrapper.get("#brainstorming-timer-duration").setValue("90");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("start_timer", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      seconds: 90,
      reveal_on_expiry: false,
      close_contributions_on_expiry: false,
    });
  });
  it("keeps duration limits and reveal options explicit and independent of closing contributions", async () => {
    const { send, current } = controls();
    await wrapper.get("#brainstorming-timer-duration").setValue("14");
    await wrapper.get("form").trigger("submit");
    expect(send).not.toHaveBeenCalled();
    expect(wrapper.get("#brainstorming-timer-start").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#brainstorming-timer-reveal").attributes("disabled")).toBeDefined();
    await wrapper.get("#brainstorming-timer-duration").setValue("86401");
    expect(wrapper.get("#brainstorming-timer-start").attributes("disabled")).toBeDefined();
    await wrapper.get("#brainstorming-timer-duration").setValue("15");
    await wrapper.setProps({
      session: {
        ...current.session!,
        configuration: { ...current.session!.configuration, private_mode: true },
      },
    });
    await wrapper.get("#brainstorming-timer-reveal").trigger("click");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(send).toHaveBeenLastCalledWith(
      "start_timer",
      expect.objectContaining({
        seconds: 15,
        reveal_on_expiry: true,
        close_contributions_on_expiry: false,
      }),
    );
  });
  it("clears the chosen reveal option if private mode is turned off before starting", async () => {
    const { current, send } = controls();
    await wrapper.setProps({
      session: {
        ...current.session!,
        configuration: { ...current.session!.configuration, private_mode: true },
      },
    });
    await wrapper.get("#brainstorming-timer-reveal").trigger("click");
    await wrapper.setProps({ session: current.session! });
    await wrapper.get("#brainstorming-timer-close").trigger("click");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(send).toHaveBeenLastCalledWith(
      "start_timer",
      expect.objectContaining({ reveal_on_expiry: false, close_contributions_on_expiry: true }),
    );
  });
  it("shows the shared countdown to participants without manager actions", () => {
    controls(timer(), undefined, false);
    expect(wrapper.get("#brainstorming-timer-countdown").text()).toBe("5:00");
    expect(wrapper.find("#brainstorming-timer-pause").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-contributions-toggle").exists()).toBe(false);
  });
  it("pauses, resumes, extends and cancels with the rendered timer version", async () => {
    const { current, send } = controls(timer());
    let version = 1;
    for (const [control, event, status] of [
      ["pause", "pause_timer", "paused"],
      ["resume", "resume_timer", "running"],
      ["extend", "extend_timer", "running"],
      ["cancel", "cancel_timer", "cancelled"],
    ] as const) {
      send.mockResolvedValue({ status: "ok", value: { id: 1, revision: version + 1 } });
      await wrapper.get(`#brainstorming-timer-${control}`).trigger("click");
      await flushPromises();
      expect(send).toHaveBeenLastCalledWith(event, {
        epoch: "epoch-one",
        session_id: 1,
        revision: version,
        timer_version: version,
        ...(control === "extend" ? { seconds: 60 } : {}),
      });
      version++;
      await wrapper.setProps({
        session: { ...current.session!, revision: version },
        timer: timer({
          status,
          version,
          deadline_at: status === "running" ? "2026-09-08T10:05:00Z" : null,
        }),
      });
    }
  });
  it("syncs once at expiry without issuing per-second requests and shows persisted completion", async () => {
    const { send } = controls(timer({ deadline_at: "2026-09-08T10:00:02Z" }));
    await vi.advanceTimersByTimeAsync(1_000);
    expect(send).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(11_000);
    expect(send).toHaveBeenCalledExactlyOnceWith(
      "sync_board",
      { epoch: "epoch-one", session_id: 1 },
      undefined,
    );
    expect(wrapper.get("#brainstorming-timer-countdown").text()).toBe("Time’s up");
    await wrapper.setProps({
      timer: timer({ status: "elapsed", outcome: "skipped_configuration" }),
    });
    expect(wrapper.get("#brainstorming-timer-finished").text()).toBe("Time’s up");
    expect(wrapper.findAll('[role="status"]')).toHaveLength(1);
    expect(wrapper.text()).toContain("session settings changed");
  });
  it.each(["running", "paused"] as const)(
    "keeps cancellation available at local zero while the persisted timer is %s",
    async (status) => {
      const { send } = controls(
        timer({
          status,
          deadline_at: status === "running" ? "2026-09-08T10:00:01Z" : null,
          remaining_seconds: 0,
        }),
      );
      await vi.advanceTimersByTimeAsync(1_000);
      expect(wrapper.find("#brainstorming-timer-pause").exists()).toBe(false);
      expect(wrapper.find("#brainstorming-timer-resume").exists()).toBe(false);
      expect(wrapper.find("#brainstorming-timer-extend").exists()).toBe(false);
      expect(wrapper.find("#brainstorming-timer-start").exists()).toBe(false);

      await wrapper.get("#brainstorming-timer-cancel").trigger("click");
      await flushPromises();
      expect(send).toHaveBeenLastCalledWith("cancel_timer", {
        epoch: "epoch-one",
        session_id: 1,
        revision: 1,
        timer_version: 1,
      });

      await wrapper.setProps({ timer: timer({ status: "elapsed", version: 2 }) });
      expect(wrapper.find("#brainstorming-timer-cancel").exists()).toBe(false);
      expect(wrapper.find("#brainstorming-timer-start").exists()).toBe(true);
    },
  );
  it("reopens contributions explicitly without starting a timer", async () => {
    const { current, send } = controls();
    await wrapper.setProps({ session: { ...current.session!, contributions_open: false } });
    await wrapper.get("#brainstorming-contributions-toggle").trigger("click");
    await flushPromises();
    expect(send).toHaveBeenCalledExactlyOnceWith("set_contributions_open", {
      epoch: "epoch-one",
      session_id: 1,
      revision: 1,
      open: true,
    });
  });
  it("keeps the chosen options and releases pending state after null or offline replies", async () => {
    const send = vi.fn().mockResolvedValue(null);
    controls(null, send);
    await wrapper.get("#brainstorming-timer-duration").setValue("75");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("#brainstorming-timer-start").attributes("disabled")).toBeUndefined();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    send.mockRejectedValue(new Error("offline"));
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("#brainstorming-timer-start").attributes("disabled")).toBeUndefined();
    expect((wrapper.get("#brainstorming-timer-duration").element as HTMLInputElement).value).toBe(
      "75",
    );
    expect(wrapper.get('[role="alert"]').text()).toContain("connection");
  });
  it("clears an old error on close without discarding the chosen options", async () => {
    controls(null, vi.fn().mockResolvedValue({ status: "error", code: "stale_timer" }));
    await wrapper.get("#brainstorming-timer-duration").setValue("75");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.getComponent(Popover).vm.$emit("update:open", false);
    await nextTick();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    wrapper.getComponent(Popover).vm.$emit("update:open", true);
    await nextTick();
    expect((wrapper.get("#brainstorming-timer-duration").element as HTMLInputElement).value).toBe(
      "75",
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
  it("asks users to review the current timer after a concurrent session edit", async () => {
    controls(timer(), vi.fn().mockResolvedValue({ status: "error", code: "stale_revision" }));
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      "Someone changed the timer. Review its current state before trying again.",
    );
  });
  it("keeps successful writes pending across popover close and reopen", async () => {
    controls(timer());
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await flushPromises();
    wrapper.getComponent(Popover).vm.$emit("update:open", false);
    wrapper.getComponent(Popover).vm.$emit("update:open", true);
    await nextTick();
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
  });
  it("does not release a new attempt when an old epoch's reply arrives", async () => {
    let finishOld!: (value: { status: string; value: { id: number; revision: number } }) => void;
    const send = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            finishOld = resolve;
          }),
      )
      .mockImplementationOnce(() => new Promise(() => {}));
    controls(timer(), send);
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await wrapper.setProps({ epoch: "epoch-two" });
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    finishOld({ status: "ok", value: { id: 1, revision: 1 } });
    await flushPromises();
    expect(send).toHaveBeenCalledTimes(2);
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeDefined();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
  it("drops a pending attempt when manager access is revoked", async () => {
    let finish!: (value: { status: string; code: string }) => void;
    controls(
      timer(),
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    await wrapper.setProps({ canManage: false });
    finish({ status: "error", code: "stale_timer" });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    await wrapper.setProps({ canManage: true });
    expect(wrapper.get("#brainstorming-timer-extend").attributes("disabled")).toBeUndefined();
  });
  it("ignores a late reply after unmounting", async () => {
    let finish!: (value: { status: string; code: string }) => void;
    controls(
      timer(),
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await wrapper.get("#brainstorming-timer-extend").trigger("click");
    wrapper.unmount();
    finish({ status: "error", code: "stale_timer" });
    await flushPromises();
    expect(warn).not.toHaveBeenCalled();
  });
  it("ignores an old reply after navigation and hides manager controls on permission changes", async () => {
    let finish!: (value: { status: string; code: string }) => void;
    const { current } = controls(
      null,
      vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
    );
    await wrapper.get("form").trigger("submit");
    await wrapper.setProps({ epoch: "new-epoch", session: { ...current.session!, id: 2 } });
    finish({ status: "error", code: "stale_timer" });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    await wrapper.setProps({ canEdit: false });
    expect(wrapper.find("form").exists()).toBe(false);
  });
});
