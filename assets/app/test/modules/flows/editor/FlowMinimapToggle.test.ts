import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import FlowMinimapToggle from "@modules/flows/editor/components/chrome/FlowMinimapToggle.vue";

describe("FlowMinimapToggle palette port", () => {
  it("registers Flow-owned commands through the injected adapter and unregisters on unmount", () => {
    const unregister = vi.fn();
    const registerCommands = vi.fn(() => unregister);

    const wrapper = mount(FlowMinimapToggle, {
      props: {
        area: null,
        editor: null,
        registerCommands,
      },
    });

    expect(registerCommands).toHaveBeenCalledWith(
      "flows",
      expect.arrayContaining([
        expect.objectContaining({ id: "flows.toggle-minimap" }),
        expect.objectContaining({ id: "flows.fit-to-view" }),
      ]),
    );

    wrapper.unmount();
    expect(unregister).toHaveBeenCalledOnce();
  });
});
