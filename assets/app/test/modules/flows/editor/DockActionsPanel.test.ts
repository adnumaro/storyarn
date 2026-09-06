import { mount } from "@vue/test-utils";
import DockActionsPanel from "@modules/flows/editor/components/chrome/dock/DockActionsPanel.vue";

describe("DockActionsPanel", () => {
  it("changes Play to Stop while the visual editor is open", async () => {
    const wrapper = mount(DockActionsPanel, {
      props: { debugPanelOpen: false, visualEditorOpen: false },
    });

    expect(wrapper.find("[data-play-icon]").exists()).toBe(true);
    expect(wrapper.find("[data-stop-icon]").exists()).toBe(false);

    await wrapper.setProps({ visualEditorOpen: true });

    expect(wrapper.find("[data-play-icon]").exists()).toBe(false);
    expect(wrapper.find("[data-stop-icon]").exists()).toBe(true);
    await wrapper.get("[data-toggle-visual-editor]").trigger("click");
    expect(wrapper.emitted("toggle-visual-editor")).toHaveLength(1);
  });
});
