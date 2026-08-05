import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsVersionControl from "../../../../live/project/settings/ProjectSettingsVersionControl.vue";
import { createMockLive } from "../../../setup";

describe("ProjectSettingsVersionControl entity auto-versioning", () => {
  it("renders and submits only entity auto-version settings", async () => {
    const live = createMockLive();
    const wrapper = mount(ProjectSettingsVersionControl, {
      props: {
        autoVersionFlows: true,
        versionUsage: null,
      },
      global: { provide: { _live_vue: live } },
    });

    const switches = wrapper.findAll('[role="switch"]');
    expect(switches).toHaveLength(3);
    expect(switches[0].attributes("aria-checked")).toBe("true");

    await switches[0].trigger("click");
    await switches[1].trigger("click");

    await wrapper.get("form").trigger("submit");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "save_version_control",
      {
        version_control: {
          auto_version_flows: "false",
          auto_version_scenes: "true",
          auto_version_sheets: "false",
        },
      },
      undefined,
    );
  });

  it("never presents unknown or zero count limits as unlimited", () => {
    const wrapper = mount(ProjectSettingsVersionControl, {
      props: {
        versionUsage: {
          projectSnapshots: { used: 0, limit: null },
          namedVersions: { used: 0, limit: 0 },
        },
      },
      global: { provide: { _live_vue: createMockLive() } },
    });

    expect(wrapper.text()).toContain("0 / Unknown");
    expect(wrapper.text()).toContain("0 / 0");
    expect(wrapper.text()).toContain("Limit reached");
    expect(wrapper.text()).not.toContain("∞");
    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(0);
  });
});
