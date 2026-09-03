import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import ProjectSettingsVersionControl from "../../../../live/project/settings/ProjectSettingsVersionControl.vue";
import { createMockLive } from "../../../setup";

describe("ProjectSettingsVersionControl entity auto-versioning", () => {
  it("saves every toggle from the server state without flipping the switch locally", async () => {
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

    expect(live.pushEvent).toHaveBeenCalledTimes(2);
    expect(vi.mocked(live.pushEvent).mock.calls[0]).toEqual([
      "save_version_control",
      {
        version_control: {
          auto_version_flows: "false",
          auto_version_scenes: "false",
          auto_version_sheets: "false",
        },
      },
      undefined,
    ]);
    // The server never acknowledged the first toggle, so the second request
    // still carries the server's value for flows.
    expect(vi.mocked(live.pushEvent).mock.calls[1]).toEqual([
      "save_version_control",
      {
        version_control: {
          auto_version_flows: "true",
          auto_version_scenes: "true",
          auto_version_sheets: "false",
        },
      },
      undefined,
    ]);
    expect(switches[0].attributes("aria-checked")).toBe("true");

    await wrapper.setProps({ autoVersionFlows: false });
    expect(wrapper.findAll('[role="switch"]')[0].attributes("aria-checked")).toBe("false");
  });

  it("never presents unknown or zero count limits as unlimited", () => {
    const wrapper = mount(ProjectSettingsVersionControl, {
      props: {
        versionUsage: {
          projectSnapshots: { used: 0, limit: null },
          namedVersions: { used: 0, limit: 0 },
        },
        usagePath: "/usage",
      },
      global: { provide: { _live_vue: createMockLive() } },
    });

    expect(wrapper.text()).toContain("0 / Unknown");
    expect(wrapper.text()).toContain("0 / 0");
    expect(wrapper.text()).toContain("Limit reached");
    expect(wrapper.text()).not.toContain("∞");
    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(0);
    expect(
      wrapper.get('[data-testid="version-control-meter-backups"]').attributes("data-meter-status"),
    ).toBe("unknown");
    expect(
      wrapper
        .get('[data-testid="version-control-meter-named_versions"]')
        .attributes("data-meter-status"),
    ).toBe("reached");
    expect(wrapper.get('a[href="/usage"]').text()).toContain("View usage");
  });

  it("renders a determinate bar for a capped quota", () => {
    const wrapper = mount(ProjectSettingsVersionControl, {
      props: {
        versionUsage: {
          projectSnapshots: { used: 2, limit: 10 },
          namedVersions: { used: 9, limit: 10 },
        },
      },
      global: { provide: { _live_vue: createMockLive() } },
    });

    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(2);
    expect(
      wrapper
        .get('[data-testid="version-control-meter-named_versions"]')
        .attributes("data-meter-status"),
    ).toBe("warning");
  });
});
