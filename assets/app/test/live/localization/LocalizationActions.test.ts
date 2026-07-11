import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import LocalizationToolbar from "../../../live/localization/toolbar/LocalizationToolbar.vue";
import ProjectSettingsLocalization from "../../../live/project/settings/ProjectSettingsLocalization.vue";
import { createMockLive } from "../../setup";

function liveGlobal(live: ReturnType<typeof createMockLive>) {
  return { config: { globalProperties: { $live: live } as never } };
}

describe("localization action failures", () => {
  it("re-enables provider actions when the LiveView push throws", async () => {
    const live = createMockLive();
    vi.mocked(live.pushEvent).mockImplementation(() => {
      throw new Error("socket closed");
    });
    vi.spyOn(console, "warn").mockImplementation(() => undefined);

    const wrapper = mount(ProjectSettingsLocalization, {
      props: { hasApiKey: true },
      global: liveGlobal(live),
    });

    await wrapper.get("form").trigger("submit");
    const saveButton = wrapper.get('[data-testid="localization-save-provider"]');
    expect(saveButton.attributes("disabled")).toBeUndefined();
    expect(wrapper.get('[role="status"]').text()).toContain("save_failed");

    const testButton = wrapper.get('[data-testid="localization-test-connection"]');
    await testButton.trigger("click");

    expect(testButton.attributes("disabled")).toBeUndefined();
    expect(wrapper.get('[role="status"]').text()).toContain("connection_failed");
  });

  it("re-enables CSV import when the browser cannot read the file", async () => {
    const live = createMockLive();
    const wrapper = mount(LocalizationToolbar, {
      props: { canEdit: true },
      global: liveGlobal(live),
    });
    const input = wrapper.get('input[type="file"]');
    const file = { text: vi.fn().mockRejectedValue(new Error("read failed")) };
    Object.defineProperty(input.element, "files", { value: [file], configurable: true });

    await input.trigger("change");
    await flushPromises();

    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get('[role="status"]').text()).toContain("Import failed");
    expect(wrapper.get("button").attributes("disabled")).toBeUndefined();
  });
});
