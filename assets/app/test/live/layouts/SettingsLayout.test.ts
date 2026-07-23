import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent } from "vue";
import SettingsLayout from "../../../live/layouts/settings/Layout.vue";

const OnboardingDialogStub = defineComponent({
  name: "OnboardingDialog",
  template: "<div />",
});

function mountLayout(
  workspaces = [
    { id: 1, name: "Admin workspace", slug: "admin" },
    { id: 2, name: "Member workspace", slug: "member" },
    { id: 3, name: "Viewer workspace", slug: "viewer" },
  ],
  workspaceSettingsAccess: Record<string, "manage" | "general"> = {
    admin: "manage",
    member: "general",
  },
  sudoGrant: string | null = null,
  aiIntegrations = false,
  currentPath = "/users/settings",
) {
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
      workspaces,
      workspaceSettingsAccess,
      sudoGrant,
      featureFlags: { aiIntegrations },
    },
    global: {
      stubs: {
        OnboardingDialog: OnboardingDialogStub,
      },
    },
  });
}

describe("SettingsLayout workspace navigation", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("shows only general settings to members and no workspace settings to viewers", () => {
    const wrapper = mountLayout();
    const hrefs = wrapper.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/users/settings/workspaces/admin/general");
    expect(hrefs).toContain("/users/settings/workspaces/admin/members");
    expect(hrefs).toContain("/users/settings/workspaces/admin/deleted-projects");

    expect(hrefs).toContain("/users/settings/workspaces/member/general");
    expect(hrefs).not.toContain("/users/settings/workspaces/member/members");
    expect(hrefs).not.toContain("/users/settings/workspaces/member/deleted-projects");

    expect(hrefs.some((href) => href?.includes("/workspaces/viewer/"))).toBe(false);
  });

  it("keeps same-named workspace sections distinct", () => {
    const wrapper = mountLayout(
      [
        { id: 1, name: "Shared name", slug: "first" },
        { id: 2, name: "Shared name", slug: "second" },
      ],
      { first: "manage", second: "general" },
    );
    const hrefs = wrapper.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/users/settings/workspaces/first/general");
    expect(hrefs).toContain("/users/settings/workspaces/second/general");
  });

  it("preserves the active sudo grant when navigating to AI integrations", () => {
    const wrapper = mountLayout(undefined, undefined, "validated grant", true);
    const hrefs = wrapper.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/users/settings/integrations?sudo_grant=validated+grant");
    expect(hrefs).toContain("/users/settings/ai-team?sudo_grant=validated+grant");
  });

  it("shows AI integrations and My AI Team as separate account destinations", () => {
    const wrapper = mountLayout(undefined, undefined, null, true);
    const hrefs = wrapper.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/users/settings/integrations");
    expect(hrefs).toContain("/users/settings/ai-team");
  });

  it("keeps the AI team overview available before the actor has a workspace", () => {
    const wrapper = mountLayout([], {}, null, true);
    const hrefs = wrapper.findAll("a").map((link) => link.attributes("href"));

    expect(hrefs).toContain("/users/settings/ai-team");
  });

  it("gives the cross-workspace overview enough room for the role summary", () => {
    const wrapper = mountLayout(undefined, undefined, null, true, "/users/settings/ai-team");

    expect(wrapper.find(".max-w-6xl").exists()).toBe(true);
  });

  it("highlights the overview item from a workspace editor without widening the editor", () => {
    const wrapper = mountLayout(undefined, undefined, null, true, "/users/settings/ai-team/admin");
    const teamLink = wrapper
      .findAll("a")
      .find((link) => link.attributes("href") === "/users/settings/ai-team");
    const profileLink = wrapper
      .findAll("a")
      .find((link) => link.attributes("href") === "/users/settings");

    expect(teamLink?.classes()).toContain("font-medium");
    expect(profileLink?.classes()).not.toContain("font-medium");
    expect(wrapper.find(".max-w-3xl").exists()).toBe(true);
    expect(wrapper.find(".max-w-6xl").exists()).toBe(false);
  });
});
