import { describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import Context from "@app/live/ideation/ExplorationContext.vue";
import type { BrainstormingReference } from "@app/live/ideation/referenceTypes";

const reference: BrainstormingReference = {
  id: 4,
  version: 2,
  relation: "origin",
  targetType: "sheet",
  targetId: 8,
  status: "changed",
  base: { name: "Original hero", fields: [] },
  current: { id: 8, type: "sheet", name: "Current hero", fields: [], href: "/sheets/8" },
  capturedAt: "2026-09-12T10:00:00Z",
};

function context(overrides: Partial<BrainstormingReference> = {}, disconnected = false) {
  const pushEvent = disconnected ? vi.fn().mockRejectedValue(new Error("Disconnected")) : vi.fn();
  const wrapper = mount(Context, {
    attachTo: document.body,
    props: { reference: { ...reference, ...overrides }, sessionId: 12, epoch: "epoch-1" },
    global: {
      provide: {
        _live_vue: {
          pushEvent,
          handleEvent: vi.fn(),
          removeHandleEvent: vi.fn(),
          upload: vi.fn(),
          ...(disconnected ? { liveSocket: {} } : {}),
        },
      },
    },
  });
  return { wrapper, pushEvent };
}

describe("Brainstorming starting context", () => {
  it("distinguishes saved and current names and opens the reference panel explicitly", async () => {
    const { wrapper, pushEvent } = context();
    expect(wrapper.text()).toContain("Current hero");
    expect(wrapper.text()).toContain("Saved context: Original hero");
    expect(wrapper.get("#brainstorming-origin-4").attributes("data-status")).toBe("changed");
    expect(wrapper.text()).toContain("Overview changed since linking");
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#brainstorming-origin-details-4").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("references_open");
    expect(pushEvent.mock.calls[0][1]).toEqual({
      session_id: 12,
      epoch: "epoch-1",
      reference_id: 4,
    });
    wrapper.unmount();
  });

  it("returns through a reauthorized server event and ignores callbacks from a previous session", async () => {
    const { wrapper, pushEvent } = context();
    expect(wrapper.find("a").exists()).toBe(false);
    await wrapper.get("#brainstorming-origin-return-4").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_return");
    expect(pushEvent.mock.calls[0][1]).toEqual({
      session_id: 12,
      epoch: "epoch-1",
      reference_id: 4,
    });
    const late = pushEvent.mock.calls[0][2];
    await wrapper.setProps({ sessionId: 13, epoch: "epoch-2" });
    late({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("[role=alert]").exists()).toBe(false);
    expect(wrapper.get("#brainstorming-origin-return-4").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("redacts all metadata and disables navigation when the origin is unavailable", async () => {
    const { wrapper, pushEvent } = context({ status: "unavailable" });
    await wrapper.setProps({ compact: true });
    expect(wrapper.text()).not.toContain("Original hero");
    expect(wrapper.text()).not.toContain("Current hero");
    expect(wrapper.text()).not.toContain("2026");
    expect(wrapper.text()).toContain("Starting content unavailable");
    expect(wrapper.get("#brainstorming-origin-return-4").attributes("disabled")).toBeDefined();
    for (const action of ["return", "details"]) {
      const control = wrapper.get(`#brainstorming-origin-${action}-4`);
      expect(control.attributes("title")).toContain("Starting content unavailable");
      expect(control.attributes("aria-label")).toContain("Starting content unavailable");
    }
    await wrapper.get("#brainstorming-origin-return-4").trigger("click");
    expect(pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each([
    { compact: false, action: "return" },
    { compact: true, action: "return" },
    { compact: true, action: "details" },
  ])(
    "reports transport failures visibly and releases controls ($action, compact=$compact)",
    async ({ compact, action }) => {
      const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
      const { wrapper } = context({}, true);
      await wrapper.setProps({ compact });
      await wrapper.get(`#brainstorming-origin-${action}-4`).trigger("click");
      await flushPromises();
      const alert = document.querySelector("[role=alert]");
      expect(alert?.textContent).toContain("The exploration could not be opened or updated");
      expect(alert?.classList.contains("sr-only")).toBe(false);
      // Compact feedback escapes the navbar's overflow-hidden containers.
      expect(wrapper.element.contains(alert)).toBe(!compact);
      expect(wrapper.get("#brainstorming-origin-return-4").attributes("disabled")).toBeUndefined();
      wrapper.unmount();
      warning.mockRestore();
    },
  );
});
