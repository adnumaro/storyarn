import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import WorkspaceDashboard from "../../../../live/workspace/dashboard/WorkspaceDashboard.vue";
import { createMockLive } from "../../../setup";

const projects = [
  {
    project: {
      id: 1,
      name: "Alpha Game",
      description: "A branching mystery",
      inserted_at_formatted: "May 01, 2026",
      updated_at: "2026-05-01T10:00:00Z",
    },
    href: "/workspaces/ws/projects/alpha-game",
  },
  {
    project: {
      id: 2,
      name: "Beta Game",
      description: "A tactical prototype",
      inserted_at_formatted: "May 02, 2026",
      updated_at: "2026-05-02T10:00:00Z",
    },
    href: "/workspaces/ws/projects/beta-game",
  },
];

function mountDashboard(props = {}) {
  const live = createMockLive();

  const wrapper = mount(WorkspaceDashboard, {
    props: {
      workspace: { name: "Test Workspace" },
      membership: { role: "owner" },
      projects,
      canCreateProject: true,
      newProjectForm: null,
      settingsUrl: "/settings",
      ...props,
    },
    global: {
      provide: {
        _live_vue: live,
      },
      stubs: {
        Dialog: { template: "<div><slot /></div>" },
        DialogContent: { template: "<div><slot /></div>" },
        DialogHeader: { template: "<div><slot /></div>" },
        DialogTitle: { template: "<div><slot /></div>" },
      },
    },
  });

  return { live, wrapper };
}

describe("WorkspaceDashboard", () => {
  it("filters projects locally without sending a LiveView search event", async () => {
    const { live, wrapper } = mountDashboard();
    const input = wrapper.get('input[type="search"]');

    await input.setValue("alpha");

    expect(wrapper.text()).toContain("Alpha Game");
    expect(wrapper.text()).not.toContain("Beta Game");
    expect(live.pushEvent).not.toHaveBeenCalledWith("search", expect.anything());
  });

  it("filters by project description", async () => {
    const { wrapper } = mountDashboard();
    const input = wrapper.get('input[type="search"]');

    await input.setValue("tactical");

    expect(wrapper.text()).not.toContain("Alpha Game");
    expect(wrapper.text()).toContain("Beta Game");
  });

  it("creates a project from the selected private template", async () => {
    const { live, wrapper } = mountDashboard({
      newProjectModalOpen: true,
      projectTemplates: [
        {
          id: 10,
          name: "Starter Kit",
          description: "A reusable setup",
          visibility: "private",
          version_number: 1,
          entity_counts: { sheets: 2, flows: 1, scenes: 0 },
        },
      ],
    });

    await wrapper.get('[data-testid="new-project-mode-private"]').trigger("click");
    await wrapper.get("#template-project-name").setValue("Starter Copy");
    await wrapper.get('[data-testid="create-project-from-template"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("create_project_from_template", {
      template_id: 10,
      name: "Starter Copy",
    });
  });
});
