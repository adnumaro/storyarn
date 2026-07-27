import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowDashboard from "../../../live/flow/dashboard/FlowDashboard.vue";
import type { FlowDashboardIssue } from "@modules/flows/types/health";
import { createMockLive } from "../../setup";

// The dashboard translates the same `flows.health.findings.*` catalog the
// editor popover does, so it must prepare `details` the same way — an array
// reaching `t()` raw renders as pretty-printed JSON inside the sentence.
function mountDashboard(issues: FlowDashboardIssue[]) {
  return mount(FlowDashboard, {
    props: {
      stats: { flow_count: 1, node_count: 0, dialogue_count: 0, word_count: 0 },
      tableData: [],
      pagination: { sortBy: "name", sortDir: "asc", page: 1, totalPages: 1, total: 1 },
      issues,
      overviewStatus: "ready",
      issuesStatus: "ready",
      canEdit: false,
    },
    global: { provide: { _live_vue: createMockLive() } },
  });
}

function issue(overrides: Partial<FlowDashboardIssue>): FlowDashboardIssue {
  return {
    id: "flow:warning:7",
    severity: "warning",
    code: "missing_output_connections",
    label: "Opening · Condition #7",
    href: "/workspaces/ws/projects/story/flows/1",
    flow_id: 1,
    entity_type: "condition",
    entity_id: 7,
    resource_id: 1,
    resource_label: "Opening",
    ...overrides,
  };
}

describe("FlowDashboard health labels", () => {
  it("renders list details as a joined string, never as JSON", () => {
    const wrapper = mountDashboard([issue({ details: { pins: ["true", "false"] } })]);
    const text = wrapper.get('a[data-severity="warning"]').text();

    expect(text).toContain("Output pins without a connection: true, false");
    expect(text).not.toContain("[");
    expect(text).not.toContain('"');
  });

  it("interpolates a scalar count detail", () => {
    const wrapper = mountDashboard([
      issue({ severity: "error", code: "multiple_entries", details: { count: 2 } }),
    ]);

    expect(wrapper.get('a[data-severity="error"]').text()).toContain("Flow has 2 Entry nodes");
  });

  it("keeps a finding without details readable", () => {
    const wrapper = mountDashboard([issue({ severity: "error", code: "missing_entry" })]);

    expect(wrapper.get('a[data-severity="error"]').text()).toContain("Flow has no Entry node");
  });
});
