import { mount } from "@vue/test-utils";
import { FileText } from "lucide-vue-next";
import { describe, expect, it } from "vitest";
import DashboardContent from "../../shell/DashboardContent.vue";
import DashboardStatCard from "../../shell/DashboardStatCard.vue";

describe("dashboard shell components", () => {
  it("renders navigable stat cards with LiveView link metadata", () => {
    const wrapper = mount(DashboardStatCard, {
      props: {
        icon: FileText,
        label: "Sheets",
        value: 12,
        href: "/workspaces/demo/projects/story/sheets",
        testId: "sheet-stat",
      },
    });

    const card = wrapper.get('[data-testid="sheet-stat"]');
    expect(card.element.tagName).toBe("A");
    expect(card.attributes("href")).toBe("/workspaces/demo/projects/story/sheets");
    expect(card.attributes("data-phx-link")).toBe("redirect");
    expect(card.text()).toContain("12");
    expect(card.text()).toContain("Sheets");
  });

  it("renders the dashboard empty state instead of slot content", () => {
    const wrapper = mount(DashboardContent, {
      props: {
        title: "Flows",
        isEmpty: true,
        emptyMessage: "No flows yet",
        emptyIcon: FileText,
      },
      slots: {
        default: "<div data-testid='dashboard-data'>Loaded</div>",
      },
    });

    expect(wrapper.text()).toContain("Flows");
    expect(wrapper.text()).toContain("No flows yet");
    expect(wrapper.find('[data-testid="dashboard-data"]').exists()).toBe(false);
  });

  it("shows skeletons while dashboard data is loading", () => {
    const wrapper = mount(DashboardContent, {
      props: {
        loading: true,
      },
    });

    expect(wrapper.get('[aria-busy="true"]').attributes("aria-busy")).toBe("true");
  });
});
