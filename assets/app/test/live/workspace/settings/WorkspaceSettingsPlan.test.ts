import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import WorkspaceSettingsPlan from "../../../../live/workspace/settings/WorkspaceSettingsPlan.vue";
import { createMockLive, setTestLocale } from "../../../setup";

function mountPlan(overrides: Record<string, unknown> = {}) {
  return mount(WorkspaceSettingsPlan, {
    props: {
      contactPath: "/contact",
      usage: {
        plan: { key: "free" },
        projects: { used: 1, limit: 3 },
        members: { used: 4, limit: 2 },
        storageBytes: { used: "350", limit: "262144000" },
        storage: {
          currentAssetsBytes: "0",
          assetTrashBytes: "0",
          fullSnapshotsBytes: "350",
          activeReservationsBytes: "0",
          totalAccountedBytes: "350",
          limitBytes: "262144000",
          remainingBytes: "262143650",
          limitKind: "limited",
        },
        ...overrides,
      },
    },
    global: { provide: { _live_vue: createMockLive() } },
  });
}

describe("WorkspaceSettingsPlan", () => {
  beforeEach(() => setTestLocale("en"));

  it("names the plan and links to the contact page", () => {
    const wrapper = mountPlan();

    expect(wrapper.get('[data-testid="workspace-plan-name"]').text()).toBe("Free");
    expect(wrapper.get("a").attributes("href")).toBe("/contact");
  });

  it("renders one meter per workspace limit with its status", () => {
    const wrapper = mountPlan();

    const projects = wrapper.get('[data-testid="workspace-plan-meter-projects"]');
    expect(projects.text()).toContain("1");
    expect(projects.text()).toContain("3");
    expect(projects.attributes("data-meter-status")).toBe("available");

    const members = wrapper.get('[data-testid="workspace-plan-meter-members"]');
    expect(members.text()).toContain("Limit reached");
    expect(members.attributes("data-meter-status")).toBe("reached");

    const storage = wrapper.get('[data-testid="workspace-plan-meter-storage"]');
    expect(storage.text()).toContain("350 B");
    expect(storage.text()).toContain("250 MB");
    expect(storage.text()).toContain("Backups 350 B");
  });

  it("shows unlimited meters without a bar", () => {
    const wrapper = mountPlan({
      projects: { used: 7, limit: null },
      storageBytes: { used: "350", limit: null },
      storage: {
        currentAssetsBytes: "0",
        assetTrashBytes: "0",
        fullSnapshotsBytes: "350",
        activeReservationsBytes: "0",
        totalAccountedBytes: "350",
        limitBytes: null,
        remainingBytes: null,
        limitKind: "unlimited",
      },
    });

    const projects = wrapper.get('[data-testid="workspace-plan-meter-projects"]');
    expect(projects.attributes("data-meter-status")).toBe("unlimited");
    expect(projects.find('[role="progressbar"]').exists()).toBe(false);
  });
});
