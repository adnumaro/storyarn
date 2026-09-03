import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProjectSettingsUsageLimits from "../../../../live/project/settings/ProjectSettingsUsageLimits.vue";

function usageLimits(overrides = {}) {
  return {
    plan: { key: "free", name: "Free" },
    project: {
      items: { used: 6, limit: 700 },
      projectSnapshots: { used: 2, limit: 10 },
      namedVersions: { used: 1, limit: 10 },
    },
    itemBreakdown: { sheets: 1, flows: 2, scenes: 1, flowNodes: 3 },
    ...overrides,
  };
}

function mountUsage(props = {}) {
  return mount(ProjectSettingsUsageLimits, {
    props: {
      usageLimits: usageLimits(),
      workspacePlanPath: "/users/settings/workspaces/acme/plan",
      ...props,
    },
  });
}

describe("ProjectSettingsUsageLimits", () => {
  it("renders the three project meters with the item breakdown", () => {
    const wrapper = mountUsage();
    const text = wrapper.text();

    expect(text).toContain("Items");
    expect(text).toContain("Sheets 1 · Flows 2 · Scenes 1 · Flow nodes 3");
    expect(text).toContain("6 / 700");
    expect(text).toContain("Backups");
    expect(text).toContain("2 / 10");
    expect(text).toContain("Named versions");
    expect(text).toContain("1 / 10");
    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(3);
    expect(
      wrapper.get('[data-testid="project-usage-meter-items"]').attributes("data-meter-status"),
    ).toBe("available");
  });

  it("no longer renders workspace-wide storage accounting", () => {
    const wrapper = mountUsage();

    expect(wrapper.text()).not.toContain("Counted storage");
    expect(wrapper.text()).not.toContain("Workspace limits");
    expect(wrapper.get('a[href="/users/settings/workspaces/acme/plan"]').text()).toContain(
      "Plan & usage",
    );
  });

  it("fails closed for unknown and zero count limits", () => {
    const base = usageLimits();
    const wrapper = mountUsage({
      usageLimits: {
        ...base,
        project: {
          ...base.project,
          projectSnapshots: { used: 0, limit: null },
          namedVersions: { used: 0, limit: 0 },
        },
      },
    });

    expect(wrapper.text()).toContain("0 / Unknown");
    expect(wrapper.text()).toContain("Limit reached");
    expect(wrapper.text()).not.toContain("No limit");
    expect(
      wrapper.get('[data-testid="project-usage-meter-backups"]').attributes("data-meter-status"),
    ).toBe("unknown");
    expect(
      wrapper
        .get('[data-testid="project-usage-meter-named_versions"]')
        .attributes("data-meter-status"),
    ).toBe("reached");
    expect(wrapper.findAll('[role="progressbar"]')).toHaveLength(1);
  });

  it("explains what to do when a quota is reached", () => {
    const base = usageLimits();
    const wrapper = mountUsage({
      usageLimits: {
        ...base,
        project: { ...base.project, namedVersions: { used: 10, limit: 10 } },
      },
    });

    const row = wrapper.get('[data-testid="project-usage-meter-named_versions"]');
    expect(row.attributes("data-meter-status")).toBe("reached");
    expect(row.text()).toContain("Delete a named version or raise the plan limit");
    expect(row.text()).toContain("Plan & usage");
  });
});
