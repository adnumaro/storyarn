import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent } from "vue";
import SettingsLayout from "../../../live/layouts/settings/Layout.vue";

const OnboardingDialogStub = defineComponent({
  name: "OnboardingDialog",
  template: "<div />",
});

function mountLayout() {
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
      workspaces: [
        { id: 1, name: "Admin workspace", slug: "admin" },
        { id: 2, name: "Member workspace", slug: "member" },
        { id: 3, name: "Viewer workspace", slug: "viewer" },
      ],
      workspaceSettingsAccess: { admin: "manage", member: "general" },
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
});
