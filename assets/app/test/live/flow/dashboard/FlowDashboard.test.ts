import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowDashboard from "../../../../live/flow/dashboard/FlowDashboard.vue";
import { createMockLive } from "../../../setup";

function mountDashboard() {
  const live = createMockLive();
  const wrapper = mount(FlowDashboard, {
    props: {
      stats: {
        flow_count: 1,
        node_count: 0,
        dialogue_count: 0,
        word_count: 0,
      },
      tableData: [],
      pagination: {
        sortBy: "name",
        sortDir: "asc",
        page: 1,
        totalPages: 1,
        total: 1,
      },
      issues: [
        {
          severity: "error",
          message: 'Flow "Opening" has no entry node',
          href: "/workspaces/ws/projects/story/flows/1",
        },
        {
          severity: "warning",
          message: 'Flow "Opening" has a disconnected node',
          href: "/workspaces/ws/projects/story/flows/1",
        },
        {
          severity: "info",
          message: "Review optional metadata",
          href: "/workspaces/ws/projects/story/flows/1",
        },
      ],
      canEdit: false,
      workspaceSlug: "ws",
      projectSlug: "story",
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });

  return wrapper;
}

describe("FlowDashboard issues", () => {
  it("renders distinct error, warning, and info severities", () => {
    const wrapper = mountDashboard();
    const error = wrapper.get('a[data-severity="error"]');
    const warning = wrapper.get('a[data-severity="warning"]');
    const info = wrapper.get('a[data-severity="info"]');

    expect(error.get('[data-testid="flow-issue-error-icon"]').classes()).toContain("text-red-500");
    expect(warning.get('[data-testid="flow-issue-warning-icon"]').classes()).toContain(
      "text-yellow-500",
    );
    expect(info.get('[data-testid="flow-issue-info-icon"]').classes()).toContain("text-blue-400");
    expect(error.attributes("href")).toBe("/workspaces/ws/projects/story/flows/1");
  });
});
