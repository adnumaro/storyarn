import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it } from "vitest";
import AccountSettingsPlanBilling from "../../../../live/account/settings/AccountSettingsPlanBilling.vue";
import { createMockLive, setTestLocale } from "../../../setup";

type Limit = number | "unlimited" | "paid_seats" | null;

function mountPlan({
  plan = { key: "free", name: "Free" },
  seats = { used: 2, limit: 2 as Limit },
  workspaces = { used: 1, limit: 1 as Limit },
} = {}) {
  return mount(AccountSettingsPlanBilling, {
    props: { contactPath: "/contact", account: { plan, seats, workspaces } },
    global: { provide: { _live_vue: createMockLive() } },
  });
}

describe("AccountSettingsPlanBilling", () => {
  beforeEach(() => setTestLocale("en"));

  it("names the plan and links to the contact page", () => {
    const wrapper = mountPlan();

    expect(wrapper.get('[data-testid="account-plan-name"]').text()).toBe("Free");
    expect(wrapper.get("a").attributes("href")).toBe("/contact");
  });

  it("shows editor seats and owned workspaces against the plan", () => {
    const wrapper = mountPlan({ seats: { used: 2, limit: 2 }, workspaces: { used: 1, limit: 3 } });

    const seats = wrapper.get('[data-testid="account-plan-meter-seats"]');
    expect(seats.text()).toContain("Editor seats");
    expect(seats.text()).toContain("Limit reached");
    expect(seats.attributes("data-meter-status")).toBe("reached");

    const workspaces = wrapper.get('[data-testid="account-plan-meter-workspaces"]');
    expect(workspaces.text()).toContain("3");
    expect(workspaces.attributes("data-meter-status")).toBe("available");
  });

  it("warns at the threshold every settings meter shares", () => {
    const wrapper = mountPlan({
      plan: { key: "beta", name: "Beta" },
      seats: { used: 8, limit: 10 },
      workspaces: { used: 1, limit: 3 },
    });

    expect(
      wrapper.get('[data-testid="account-plan-meter-seats"]').attributes("data-meter-status"),
    ).toBe("warning");
  });

  it("presents paid seats as bought per editor, without a bar", () => {
    const wrapper = mountPlan({
      plan: { key: "pro", name: "Pro" },
      seats: { used: 4, limit: "paid_seats" },
      workspaces: { used: 1, limit: 3 },
    });

    const seats = wrapper.get('[data-testid="account-plan-meter-seats"]');
    expect(seats.text()).toContain("Per paid seat");
    expect(seats.find('[role="progressbar"]').exists()).toBe(false);
  });

  it("never presents a missing limit as unlimited", () => {
    const wrapper = mountPlan({ workspaces: { used: 1, limit: null } });

    const workspaces = wrapper.get('[data-testid="account-plan-meter-workspaces"]');
    expect(workspaces.attributes("data-meter-status")).toBe("unknown");
    expect(workspaces.text()).not.toContain("Unlimited");
  });
});
