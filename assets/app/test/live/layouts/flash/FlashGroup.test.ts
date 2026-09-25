import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import FlashGroup from "../../../../live/layouts/flash/FlashGroup.vue";
import { createMockLive, setTestLocale } from "../../../setup";

const network = {
  clientTitle: "Offline",
  serverTitle: "Server error",
  reconnecting: "Reconnecting",
};

function mountFlash(flash: Record<string, unknown>, live = createMockLive()) {
  const wrapper = mount(FlashGroup, {
    props: { flash, network },
    global: { provide: { _live_vue: live } },
  });

  return { wrapper, live };
}

describe("FlashGroup", () => {
  beforeEach(() => setTestLocale("en"));

  it("links a limit notice to Plan & usage", () => {
    const { wrapper } = mountFlash({
      limit: {
        message: "Project limit reached for your plan",
        planPath: "/users/settings/workspaces/acme/plan",
      },
    });

    const toast = wrapper.get("#flash-limit");
    expect(toast.text()).toContain("Project limit reached for your plan");

    const link = toast.get('[data-testid="flash-limit-plan-link"]');
    expect(link.attributes("href")).toBe("/users/settings/workspaces/acme/plan");
    expect(link.text()).toBe("View plans");
  });

  it("shows the notice alone to someone who cannot manage the plan", () => {
    const { wrapper } = mountFlash({
      limit: { message: "Item limit reached for your plan", planPath: null },
    });

    expect(wrapper.get("#flash-limit").text()).toContain("Item limit reached for your plan");
    expect(wrapper.find('[data-testid="flash-limit-plan-link"]').exists()).toBe(false);
  });

  it("dismisses a limit notice from its close button", async () => {
    const { wrapper, live } = mountFlash({
      limit: { message: "Member limit reached for your plan.", planPath: null },
    });

    await wrapper.get('#flash-limit button[aria-label="Dismiss"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("lv:clear-flash", { key: "limit" });
    expect(wrapper.find("#flash-limit").exists()).toBe(false);
  });

  it("keeps the other toasts as they were", () => {
    const { wrapper } = mountFlash({ error: "Could not create flow." });

    expect(wrapper.get("#flash-error button").text()).toContain("Could not create flow.");
    expect(wrapper.find("#flash-limit").exists()).toBe(false);
  });
});
