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
      currentPath: "/users/settings",
      workspaces,
      workspaceSettingsAccess,
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
});
