import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import WorkspaceSettingsUsage from "../../../../live/workspace/settings/WorkspaceSettingsUsage.vue";
import { createMockLive, setTestLocale } from "../../../setup";

function mountUsage(
  overrides: Record<string, unknown> = {},
  { planPath = null }: { planPath?: string | null } = {},
) {
  return mount(WorkspaceSettingsUsage, {
    props: {
      planPath,
      usage: {
        projects: { used: 3, limit: 3 },
        storageBytes: { used: "350", limit: "524288000" },
        storage: {
          currentAssetsBytes: "0",
          assetTrashBytes: "0",
          fullSnapshotsBytes: "350",
          activeReservationsBytes: "0",
          totalAccountedBytes: "350",
          limitBytes: "524288000",
          remainingBytes: "524287650",
          limitKind: "limited",
        },
        ...overrides,
      },
    },
    global: { provide: { _live_vue: createMockLive() } },
  });
}

describe("WorkspaceSettingsUsage", () => {
  beforeEach(() => setTestLocale("en"));

  it("renders one meter per workspace limit with its status", () => {
    const wrapper = mountUsage();

    const projects = wrapper.get('[data-testid="workspace-usage-meter-projects"]');
    expect(projects.text()).toContain("3");
    expect(projects.text()).toContain("Limit reached");
    expect(projects.attributes("data-meter-status")).toBe("reached");

    const storage = wrapper.get('[data-testid="workspace-usage-meter-storage"]');
    expect(storage.text()).toContain("350 B");
    expect(storage.text()).toContain("500 MB");
    expect(storage.text()).toContain("Backups 350 B");
  });

  it("shows no editor seats: they are an account total", () => {
    const wrapper = mountUsage();

    expect(wrapper.find('[data-testid="workspace-usage-meter-members"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Members");
  });

  it("links the owner to Plan & billing", () => {
    const wrapper = mountUsage({}, { planPath: "/users/settings/plan" });

    const link = wrapper.get('[data-testid="workspace-usage-plan-link"]');
    expect(link.attributes("href")).toBe("/users/settings/plan");
    expect(link.text()).toBe("Plan & billing");
  });

  it("gives admins and members no plan link", () => {
    const wrapper = mountUsage();

    expect(wrapper.find('[data-testid="workspace-usage-plan-link"]').exists()).toBe(false);
    expect(wrapper.find("a").exists()).toBe(false);
  });

  it("shows unlimited meters without a bar", () => {
    const wrapper = mountUsage({
      projects: { used: 7, limit: "unlimited" },
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

    const projects = wrapper.get('[data-testid="workspace-usage-meter-projects"]');
    expect(projects.attributes("data-meter-status")).toBe("unlimited");
    expect(projects.text()).toContain("Unlimited");
    expect(projects.text()).not.toContain("/");
    expect(projects.find('[role="progressbar"]').exists()).toBe(false);
  });

  it("never presents a missing count limit as unlimited", () => {
    const wrapper = mountUsage({ projects: { used: 3, limit: null } });

    const projects = wrapper.get('[data-testid="workspace-usage-meter-projects"]');
    expect(projects.attributes("data-meter-status")).toBe("unknown");
    expect(projects.text()).not.toContain("Unlimited");
  });
});
