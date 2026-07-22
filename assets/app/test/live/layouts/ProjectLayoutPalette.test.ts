import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defineComponent } from "vue";
import ProjectLayout from "../../../live/layouts/project/Layout.vue";
import { paletteGroups, resetPaletteRegistry } from "../../../shared/command-palette/registry";

const EmptyStub = defineComponent({ template: "<div><slot /></div>" });

function mountLayout(canManageProject: boolean) {
  vi.stubGlobal("matchMedia", () => ({
    matches: true,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }));

  return mount(ProjectLayout, {
    props: {
      chrome: {
        activeTool: "sheets",
        hasTree: false,
        mainSidebarOpen: false,
        projectName: "Veilbreak",
        workspaceName: "Acme",
        showToolSwitcher: true,
        isSuperAdmin: false,
        canManageProject,
      },
      currentUser: { id: 1, email: "user@example.com", displayName: "User" },
      urls: {
        workspace: "/workspaces/acme",
        projectSettings: "/workspaces/acme/projects/veilbreak/settings",
        trash: "/workspaces/acme/projects/veilbreak/settings/trash",
        accountSettings: "/users/settings",
        workspaces: "/workspaces",
        logout: "/users/log-out",
        tools: {
          dashboard: "/workspaces/acme/projects/veilbreak",
          sheets: "/workspaces/acme/projects/veilbreak/sheets",
        },
      },
    },
    global: {
      stubs: {
        ProjectNavbarContext: EmptyStub,
        ProjectNavbarAccount: EmptyStub,
        OnboardingDialog: EmptyStub,
      },
    },
  });
}

function commandIds(): string[] {
  return paletteGroups.value.flatMap((group) => group.commands.map((command) => command.id));
}

describe("project layout palette permissions", () => {
  beforeEach(resetPaletteRegistry);
  afterEach(() => vi.unstubAllGlobals());

  it("does not register project settings for editors or viewers", () => {
    const wrapper = mountLayout(false);

    expect(commandIds()).toContain("project.go-to.sheets");
    expect(commandIds().some((id) => id.startsWith("project.settings."))).toBe(false);

    wrapper.unmount();
  });

  it("registers project settings for project owners", () => {
    const wrapper = mountLayout(true);

    expect(commandIds()).toContain("project.settings.general");
    expect(commandIds()).toContain("project.settings.members");

    wrapper.unmount();
  });
});
