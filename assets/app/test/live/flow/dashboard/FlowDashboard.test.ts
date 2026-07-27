import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowDashboard from "../../../../live/flow/dashboard/FlowDashboard.vue";
import DashboardIssueFilters from "../../../../components/dashboard/DashboardIssueFilters.vue";
import DashboardPagination from "../../../../components/dashboard/DashboardPagination.vue";
import { createMockLive } from "../../../setup";

const issueFilterOptions = {
  totals: { severity: 30, code: 30, resource: 30 },
  severities: [
    { value: "error", count: 10 },
    { value: "warning", count: 15 },
    { value: "info", count: 5 },
  ],
  codes: [
    { value: "empty_condition", count: 5 },
    { value: "isolated_node", count: 15 },
    { value: "missing_entry", count: 10 },
  ],
  resources: [{ value: "1", label: "Opening", count: 30 }],
};

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
      tableData: [
        {
          id: 1,
          name: "Opening",
          href: "/workspaces/ws/projects/story/flows/1",
          is_main: true,
          node_count: 0,
          dialogue_count: 0,
          condition_count: 0,
          word_count: 0,
          updated_at: "2026-07-26T12:00:00Z",
        },
      ],
      pagination: {
        sortBy: "name",
        sortDir: "asc",
        page: 1,
        totalPages: 1,
        total: 1,
      },
      issues: [
        // The server sends a CODE and the location; Vue resolves the sentence
        // against `flows.health.findings.*`, the same catalog the editor popover
        // uses. Sheets' dashboard has always worked this way.
        {
          id: "flow:error:1",
          severity: "error",
          code: "missing_entry",
          label: "Opening",
          details: {},
          href: "/workspaces/ws/projects/story/flows/1",
          flow_id: 1,
          entity_type: "flow",
          entity_id: null,
          resource_id: 1,
          resource_label: "Opening",
        },
        {
          id: "flow:warning:42",
          severity: "warning",
          code: "isolated_node",
          label: "Opening · Dialogue #42",
          details: {},
          href: "/workspaces/ws/projects/story/flows/1",
          flow_id: 1,
          entity_type: "dialogue",
          entity_id: 42,
          resource_id: 1,
          resource_label: "Opening",
        },
        {
          id: "flow:info:7",
          severity: "info",
          code: "empty_condition",
          label: "Opening · Condition #7",
          details: {},
          href: "/workspaces/ws/projects/story/flows/1",
          flow_id: 1,
          entity_type: "condition",
          entity_id: 7,
          resource_id: 1,
          resource_label: "Opening",
        },
      ],
      issuePagination: { page: 1, totalPages: 2, total: 30, unfilteredTotal: 30 },
      issueFilterOptions,
      overviewStatus: "ready",
      issuesStatus: "ready",
      canEdit: false,
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });

  return { live, wrapper };
}

describe("FlowDashboard issues", () => {
  it("forwards complete faceted counts to the shared issue filters", () => {
    const { wrapper } = mountDashboard();

    expect(wrapper.getComponent(DashboardIssueFilters).props("options")).toEqual(
      issueFilterOptions,
    );
  });

  it("disables issue filters during a background issue refresh", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "refreshing" });

    expect(wrapper.getComponent(DashboardIssueFilters).props("disabled")).toBe(true);
  });

  it("renders distinct error, warning, and info severities", () => {
    const { wrapper } = mountDashboard();
    const error = wrapper.get('a[data-severity="error"]');
    const warning = wrapper.get('a[data-severity="warning"]');
    const info = wrapper.get('a[data-severity="info"]');

    expect(error.get('[data-testid="flow-issue-error-icon"]').classes()).toContain("text-red-500");
    expect(warning.get('[data-testid="flow-issue-warning-icon"]').classes()).toContain(
      "text-yellow-500",
    );
    expect(info.get('[data-testid="flow-issue-info-icon"]').classes()).toContain("text-blue-400");
    expect(error.get(".sr-only").text()).toBe("Error:");
    expect(warning.get(".sr-only").text()).toBe("Warning:");
    expect(info.get(".sr-only").text()).toBe("Information:");
    expect(error.attributes("href")).toBe("/workspaces/ws/projects/story/flows/1");
  });

  it("keeps loaded issues visible while the independent overview is loading", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ overviewStatus: "loading", issuesStatus: "ready" });

    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);
    expect(wrapper.getComponent(DashboardIssueFilters).props("codeLabel")!("missing_entry")).toBe(
      "Missing Entry node",
    );
  });

  it("shows an explicit initial error and retries the overview load", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({
      overviewStatus: "error",
      pagination: { sortBy: "name", sortDir: "asc", page: 1, totalPages: 1, total: 0 },
    });

    expect(wrapper.get('[data-testid="dashboard-overview-error"]').attributes("role")).toBe(
      "alert",
    );
    expect(wrapper.text()).not.toContain("No flows yet");

    await wrapper.get('[data-testid="dashboard-overview-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("keeps overview content under a persistent stale warning and retries only it", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({ overviewStatus: "stale" });

    const stale = wrapper.get('[data-testid="dashboard-overview-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded data");
    expect(wrapper.find('a[href="/workspaces/ws/projects/story/flows/1"]').exists()).toBe(true);

    await wrapper.get('[data-testid="dashboard-overview-stale-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("announces the independent issues loading state", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "loading" });

    const status = wrapper.get('[data-testid="flow-issues-loading"]');
    expect(status.attributes("role")).toBe("status");
    expect(status.text()).toContain("Loading issues");
  });

  it("shows an independent initial issues error with its own retry", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({
      issuesStatus: "error",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.get('[data-testid="flow-issues-error"]').attributes("role")).toBe("alert");
    expect(wrapper.find('a[href="/workspaces/ws/projects/story/flows/1"]').exists()).toBe(true);

    await wrapper.get('[data-testid="flow-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("preserves issues under a persistent stale warning and offers retry", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "stale" });

    const stale = wrapper.get('[data-testid="flow-issues-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded results");
    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);

    await wrapper.get('[data-testid="flow-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("does not reveal an empty issues section during a background refresh", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({
      issuesStatus: "refreshing",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.find('[data-testid="flow-dashboard-issues"]').exists()).toBe(false);
  });

  it("uses independent LiveView events for issue filters and pages", () => {
    const { live, wrapper } = mountDashboard();

    wrapper
      .getComponent(DashboardIssueFilters)
      .vm.$emit("change", { filter: "code", value: "missing_entry" });

    const paginators = wrapper.findAllComponents(DashboardPagination);
    expect(paginators).toHaveLength(2);
    paginators.at(-1)?.vm.$emit("page", 2);

    expect(live.pushEvent).toHaveBeenCalledWith(
      "filter_flow_issues",
      {
        filter: "code",
        value: "missing_entry",
      },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenCalledWith("page_flow_issues", { page: 2 }, undefined);
  });
});
