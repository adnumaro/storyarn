import { afterEach, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import { nextTick } from "vue";
import BrainstormingSidebar from "@modules/ideation/BrainstormingSidebar.vue";
import { useBoardConnection } from "@modules/ideation/composables/useBoardConnection";
import { createMockLive, createPromiseMockLive, withSetup } from "../../setup";
import { board } from "./fixtures";

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it("does not poll idle boards and resynchronizes when the browser becomes available", async () => {
  vi.useFakeTimers();
  const live = createMockLive();
  const { app } = withSetup(() => useBoardConnection(() => board(), vi.fn()), { live });
  await vi.advanceTimersByTimeAsync(120_000);
  expect(live.pushEvent).not.toHaveBeenCalled();

  window.dispatchEvent(new Event("online"));
  expect(live.pushEvent).toHaveBeenCalledTimes(1);
  expect(live.pushEvent).toHaveBeenLastCalledWith(
    "sync_board",
    { epoch: "epoch-one", session_id: 1 },
    expect.any(Function),
  );
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
  document.dispatchEvent(new Event("visibilitychange"));
  expect(live.pushEvent).toHaveBeenCalledTimes(2);
  app.unmount();
  window.dispatchEvent(new Event("online"));
  document.dispatchEvent(new Event("visibilitychange"));
  expect(live.pushEvent).toHaveBeenCalledTimes(2);
});

it("releases sidebar controls after a null reply and permits another session creation", async () => {
  vi.stubGlobal(
    "matchMedia",
    vi.fn(() => ({ matches: true })),
  );
  const send = vi.fn().mockResolvedValueOnce(null).mockResolvedValueOnce({ status: "ok" });
  const live = createPromiseMockLive({}, send);
  const wrapper = mount(BrainstormingSidebar, {
    props: { board: board(), baseUrl: "/brainstorming" },
    global: {
      provide: { _live_vue: live },
      stubs: {
        SidebarFrame: { template: "<div><slot /></div>" },
        BoardSelect: true,
        ConfirmDialog: true,
        LiveLink: true,
      },
    },
  });
  const create = wrapper.get("#new-brainstorming-session");
  await create.trigger("click");
  await flushPromises();
  expect(create.attributes("disabled")).toBeUndefined();
  await create.trigger("click");
  await flushPromises();
  expect(send).toHaveBeenCalledTimes(2);
  expect(create.attributes("disabled")).toBeUndefined();
  wrapper.unmount();
});

it("updates the active session after a server patch without a page-loading event", async () => {
  const previousUrl = window.location.href;
  window.history.replaceState({}, "", "/brainstorming/1");
  const initial = board();
  const session = initial.session!;
  const wrapper = mount(BrainstormingSidebar, {
    props: {
      board: { ...initial, sessions: [session, { ...session, id: 2, title: "Second" }] },
      baseUrl: "/brainstorming",
    },
    global: {
      provide: { _live_vue: createMockLive() },
      stubs: {
        SidebarFrame: { template: "<div><slot /></div>" },
        BoardSelect: true,
        ConfirmDialog: true,
      },
    },
  });

  try {
    await nextTick();
    expect(wrapper.get('a[href="/brainstorming/1"]').attributes("aria-current")).toBe("page");
    window.history.pushState({}, "", "/brainstorming/2");
    window.dispatchEvent(new CustomEvent("phx:navigate", { detail: { patch: true } }));
    await nextTick();
    expect(wrapper.get('a[href="/brainstorming/1"]').attributes("aria-current")).toBeUndefined();
    expect(wrapper.get('a[href="/brainstorming/2"]').attributes("aria-current")).toBe("page");
  } finally {
    wrapper.unmount();
    window.history.replaceState({}, "", previousUrl);
  }
});
