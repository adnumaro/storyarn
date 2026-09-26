import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ReadOnlyBanner from "../../shell/ReadOnlyBanner.vue";
import { createMockLive } from "../setup";

function mountBanner(notice: InstanceType<typeof ReadOnlyBanner>["$props"]["notice"]) {
  return mount(ReadOnlyBanner, {
    props: { notice },
    global: { provide: { _live_vue: createMockLive() } },
  });
}

describe("ReadOnlyBanner", () => {
  it("tells the owner which limits the account exceeds and what to do", () => {
    const wrapper = mountBanner({
      owner: true,
      reasons: ["workspaces_per_user", "storage_bytes_per_workspace", "not_a_limit"],
      planPath: "/users/settings/plan",
    });

    expect(wrapper.text()).toContain("This workspace is read-only");
    expect(wrapper.findAll("li").map((item) => item.text())).toEqual([
      "It owns more workspaces than the plan includes.",
      "A workspace uses more storage than the plan includes.",
    ]);
    expect(wrapper.get('[data-testid="read-only-banner-plan-link"]').attributes("href")).toBe(
      "/users/settings/plan",
    );
  });

  it("tells everyone else whom to ask, and nothing about the plan", () => {
    const wrapper = mountBanner({ owner: false, ownerName: "Ada" });

    expect(wrapper.text()).toContain("Contact its owner, Ada, to edit it again.");
    expect(wrapper.find("li").exists()).toBe(false);
    expect(wrapper.find('[data-testid="read-only-banner-plan-link"]').exists()).toBe(false);
  });
});
