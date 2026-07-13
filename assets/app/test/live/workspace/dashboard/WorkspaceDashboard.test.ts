import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
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
        Dialog: {
          props: ["open"],
          emits: ["update:open"],
          template:
            '<div data-testid="new-project-dialog" :data-open="String(open)"><button data-testid="dialog-close" @click="$emit(\'update:open\', false)" /><slot /></div>',
        },
        DialogContent: { template: "<div><slot /></div>" },
        DialogDescription: { template: "<div><slot /></div>" },
        DialogHeader: { template: "<div><slot /></div>" },
        DialogTitle: { template: "<div><slot /></div>" },
        NewProjectForm: { template: "<div />" },
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

  it("syncs new project modal visibility with LiveView", async () => {
    const { live, wrapper } = mountDashboard({ newProjectForm: {} });

    await wrapper.get('[data-testid="new-project-open"]').trigger("click");

    expect(wrapper.get('[data-testid="new-project-dialog"]').attributes("data-open")).toBe("true");
    expect(live.pushEvent).toHaveBeenCalledWith("set_new_project_modal_open", { open: true });
  });

  it("closes the new project modal optimistically", async () => {
    const { live, wrapper } = mountDashboard({
      newProjectForm: {},
      newProjectModalOpen: true,
    });

    await wrapper.get('[data-testid="dialog-close"]').trigger("click");

    expect(wrapper.get('[data-testid="new-project-dialog"]').attributes("data-open")).toBe("false");
    expect(live.pushEvent).toHaveBeenCalledWith("set_new_project_modal_open", { open: false });
  });

  it("creates a project from the selected private template", async () => {
    const { live, wrapper } = mountDashboard({
      templateCreation: {
        templates: [
          {
            id: 10,
            name: "Starter Kit",
            description: "A reusable setup",
            visibility: "private",
            version_number: 1,
            entity_counts: { sheets: 2, flows: 1, scenes: 0 },
          },
        ],
        installations: [],
      },
    });

    await wrapper.get('[data-testid="new-project-mode-private"]').trigger("click");
    await wrapper.get("#template-project-name").setValue("Starter Copy");
    vi.mocked(live.pushEvent).mockImplementation((_event, _payload, callback) =>
      callback?.({ status: "queued" }),
    );
    await wrapper.get('[data-testid="create-project-from-template"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "create_project_from_template",
      {
        template_id: 10,
        name: "Starter Copy",
      },
      expect.any(Function),
    );
    expect(wrapper.get('[data-testid="new-project-dialog"]').attributes("data-open")).toBe("false");
  });

  it("shows durable template installations in the project grid", () => {
    const { wrapper } = mountDashboard({
      projects: [],
      templateCreation: {
        templates: [],
        installations: [
          {
            id: 42,
            project_name: "Storyarn Demo",
            status: "running",
            stage: "materializing",
            template_id: 10,
            template_version_id: 11,
          },
        ],
      },
    });

    expect(wrapper.get('[data-testid="template-installation-42"]').text()).toContain(
      "Storyarn Demo",
    );
    expect(wrapper.text()).not.toContain("No projects yet");
  });

  it("prevents duplicate submissions while the request is pending", async () => {
    const { live, wrapper } = mountDashboard({
      templateCreation: {
        templates: [
          {
            id: 10,
            name: "Starter Kit",
            visibility: "private",
            version_number: 1,
          },
        ],
        installations: [],
      },
    });

    await wrapper.get('[data-testid="new-project-mode-private"]').trigger("click");
    await wrapper.get('[data-testid="create-project-from-template"]').trigger("click");
    await wrapper.get('[data-testid="create-project-from-template"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-testid="create-project-from-template"]').attributes()).toHaveProperty(
      "disabled",
    );
    expect(wrapper.text()).toContain("Starting");
  });
});
