import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent } from "vue";
import SettingsLayout from "../../../live/layouts/settings/Layout.vue";

const OnboardingDialogStub = defineComponent({
  name: "OnboardingDialog",
  template: "<div />",
});

interface NavWorkspace {
  id: number;
  slug: string;
  name: string;
  access: "manage" | "general";
  owner: boolean;
}

interface NavProject {
  id: number;
  slug: string;
  name: string;
  workspaceSlug: string;
  access: "owner" | "editor" | "viewer";
}

interface Nav {
  workspace: NavWorkspace | null;
  workspaces: NavWorkspace[];
  project: NavProject | null;
  projects: { id: number; slug: string; name: string }[];
}

const ownerWorkspace: NavWorkspace = {
  id: 1,
  slug: "admin",
  name: "Admin workspace",
  access: "manage",
  owner: true,
};

const memberWorkspace: NavWorkspace = {
  id: 2,
  slug: "member",
  name: "Member workspace",
  access: "general",
  owner: false,
};

function nav(overrides: Partial<Nav> = {}): Nav {
  return {
    workspace: ownerWorkspace,
    workspaces: [ownerWorkspace, memberWorkspace],
    project: null,
    projects: [],
    ...overrides,
  };
}

function mountLayout({
  settingsNav = nav(),
  sudoGrant = null,
  aiIntegrations = false,
  currentPath = "/users/settings",
  title = null,
}: {
  settingsNav?: Nav | null;
  sudoGrant?: string | null;
  aiIntegrations?: boolean;
  currentPath?: string;
  title?: string | null;
} = {}) {
  vi.stubGlobal(
    "matchMedia",
    vi.fn().mockReturnValue({
      matches: true,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }),
  );

  return mount(SettingsLayout, {
    props: {
      currentPath,
      settingsNav,
      sudoGrant,
      title,
      featureFlags: { aiIntegrations },
    },
    global: {
      stubs: {
        OnboardingDialog: OnboardingDialogStub,
      },
    },
  });
}

function hrefs(wrapper: ReturnType<typeof mountLayout>): (string | undefined)[] {
  return wrapper.findAll("a").map((link) => link.attributes("href"));
}

describe("SettingsLayout rail", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("lists the personal settings for every user", () => {
    const links = hrefs(mountLayout({ settingsNav: null }));

    expect(links).toContain("/users/settings");
    expect(links).toContain("/users/settings/security");
    expect(links).toContain("/users/settings/tutorials");
    expect(links.some((href) => href?.includes("/workspaces/"))).toBe(false);
  });

  it("shows the current workspace group with every page for a manager", () => {
    const wrapper = mountLayout();
    const links = hrefs(wrapper);

    expect(links).toContain("/users/settings/workspaces/admin/general");
    expect(links).toContain("/users/settings/workspaces/admin/members");
    expect(links).toContain("/users/settings/workspaces/admin/imports");
    expect(links).toContain("/users/settings/workspaces/admin/deleted-projects");
    expect(wrapper.find('[data-settings-group="workspace"]').text()).toContain("Admin workspace");
    expect(wrapper.findAll("[data-settings-locked]")).toHaveLength(0);
  });

  it("locks the general page for a manager who is not the owner", () => {
    const wrapper = mountLayout({
      settingsNav: nav({ workspace: { ...ownerWorkspace, owner: false } }),
    });
    const general = wrapper
      .findAll("a")
      .find((link) => link.attributes("href") === "/users/settings/workspaces/admin/general");

    expect(general?.find("[data-settings-locked]").exists()).toBe(true);
  });

  it("shows only the locked general page to a plain member", () => {
    const wrapper = mountLayout({
      settingsNav: nav({ workspace: memberWorkspace }),
    });
    const links = hrefs(wrapper);

    expect(links).toContain("/users/settings/workspaces/member/general");
    expect(links).not.toContain("/users/settings/workspaces/member/members");
    expect(links).not.toContain("/users/settings/workspaces/member/imports");
    expect(wrapper.findAll("[data-settings-locked]")).toHaveLength(1);
  });

  it("offers a workspace switcher only when there is more than one workspace", () => {
    const withMany = mountLayout();
    const withOne = mountLayout({ settingsNav: nav({ workspaces: [ownerWorkspace] }) });

    expect(withMany.find('[data-settings-group="workspace"] button[title]').exists()).toBe(true);
    expect(withOne.find('[data-settings-group="workspace"] button[title]').exists()).toBe(false);
  });

  it("lists project settings for an editor with owner-only pages locked", () => {
    const wrapper = mountLayout({
      settingsNav: nav({
        project: {
          id: 7,
          slug: "veilbreak",
          name: "Veilbreak",
          workspaceSlug: "admin",
          access: "editor",
        },
      }),
      currentPath: "/workspaces/admin/projects/veilbreak/settings/trash",
    });
    const links = hrefs(wrapper);
    const base = "/workspaces/admin/projects/veilbreak/settings";

    expect(links).toContain(base);
    expect(links).toContain(`${base}/trash`);
    expect(links).toContain(`${base}/export-import`);

    const general = wrapper.findAll("a").find((link) => link.attributes("href") === base);
    const trash = wrapper.findAll("a").find((link) => link.attributes("href") === `${base}/trash`);

    expect(general?.find("[data-settings-locked]").exists()).toBe(true);
    expect(trash?.find("[data-settings-locked]").exists()).toBe(false);
    expect(trash?.classes()).toContain("font-medium");
  });

  it("hides project settings from a project viewer", () => {
    const wrapper = mountLayout({
      settingsNav: nav({
        project: {
          id: 7,
          slug: "veilbreak",
          name: "Veilbreak",
          workspaceSlug: "admin",
          access: "viewer",
        },
      }),
    });

    expect(wrapper.find('[data-settings-group="project"]').exists()).toBe(false);
  });

  it("preserves the active sudo grant on sensitive personal links", () => {
    const links = hrefs(mountLayout({ sudoGrant: "validated grant", aiIntegrations: true }));

    expect(links).toContain("/users/settings?sudo_grant=validated+grant");
    expect(links).toContain("/users/settings/integrations?sudo_grant=validated+grant");
    expect(links).toContain("/users/settings/ai-team?sudo_grant=validated+grant");
  });

  it("keeps the AI team overview available before the actor has a workspace", () => {
    const links = hrefs(mountLayout({ settingsNav: null, aiIntegrations: true }));

    expect(links).toContain("/users/settings/ai-team");
  });

  it("highlights the overview item from a workspace editor and widens only the overview", () => {
    const editor = mountLayout({
      aiIntegrations: true,
      currentPath: "/users/settings/ai-team/admin",
    });
    const overview = mountLayout({ aiIntegrations: true, currentPath: "/users/settings/ai-team" });

    const teamLink = editor
      .findAll("a")
      .find((link) => link.attributes("href") === "/users/settings/ai-team");
    const profileLink = editor
      .findAll("a")
      .find((link) => link.attributes("href") === "/users/settings");

    expect(teamLink?.classes()).toContain("font-medium");
    expect(profileLink?.classes()).not.toContain("font-medium");
    expect(editor.find('[data-testid="settings-content"]').classes()).toContain("max-w-[720px]");
    expect(overview.find('[data-testid="settings-content"]').classes()).toContain("max-w-[960px]");
  });

  it("names the scope and page in the mobile header", () => {
    const wrapper = mountLayout({
      currentPath: "/users/settings/workspaces/admin/members",
    });

    const header = wrapper.find("header.lg\\:hidden");
    expect(header.text()).toContain("Admin workspace");
    expect(header.text()).toContain("Members");
  });

  it("asks the command palette to open from the search box", () => {
    const listener = vi.fn();
    window.addEventListener("storyarn:open-palette", listener);

    const wrapper = mountLayout();
    wrapper
      .findAll("button")
      .find((button) => button.text().includes("Search"))
      ?.trigger("click");

    expect(listener).toHaveBeenCalledTimes(1);
    window.removeEventListener("storyarn:open-palette", listener);
  });
});
