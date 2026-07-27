import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SheetDashboard from "../../../../live/sheet/dashboard/SheetDashboard.vue";
import DashboardIssueFilters from "../../../../components/dashboard/DashboardIssueFilters.vue";
import DashboardPagination from "../../../../components/dashboard/DashboardPagination.vue";
import DropdownMenuItem from "../../../../components/ui/dropdown-menu/DropdownMenuItem.vue";
import { createMockLive } from "../../../setup";

type SheetDashboardProps = InstanceType<typeof SheetDashboard>["$props"];

const issueFilterOptions = {
  totals: { severity: 30, code: 30, resource: 30 },
  severities: [
    { value: "error", count: 10 },
    { value: "warning", count: 10 },
    { value: "info", count: 10 },
  ],
  codes: [
    { value: "empty_leaf_sheet", count: 10 },
    { value: "missing_sheet_shortcut", count: 10 },
    { value: "required_block_empty", count: 10 },
  ],
  resources: [
    { value: "2", label: "Empty Sheet", count: 10 },
    { value: "1", label: "Hero", count: 20 },
  ],
};

function mountDashboard(overrides: Partial<SheetDashboardProps> = {}) {
  const live = createMockLive();

  const wrapper = mount(SheetDashboard, {
    props: {
      stats: {
        sheet_count: 1,
        block_count: 0,
        variable_count: 0,
        variables_in_use: 0,
        word_count: 0,
      },
      tableData: [
        {
          id: 1,
          name: "Hero",
          href: "/workspaces/ws/projects/story/sheets/1",
          block_count: 0,
          variable_count: 0,
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
        {
          id: "sheet:error:1",
          severity: "error",
          code: "missing_sheet_shortcut",
          label: "Hero",
          href: "/workspaces/ws/projects/story/sheets/1",
          sheet_id: 1,
          resource_id: 1,
          resource_label: "Hero",
        },
        {
          id: "sheet:warning:1",
          severity: "warning",
          code: "required_block_empty",
          label: "Hero · Biography",
          href: "/workspaces/ws/projects/story/sheets/1",
          sheet_id: 1,
          resource_id: 1,
          resource_label: "Hero",
        },
        {
          id: "sheet:info:2",
          severity: "info",
          code: "empty_leaf_sheet",
          label: "Empty Sheet",
          href: "/workspaces/ws/projects/story/sheets/2",
          sheet_id: 2,
          resource_id: 2,
          resource_label: "Empty Sheet",
        },
      ],
      issuePagination: { page: 1, totalPages: 2, total: 30, unfilteredTotal: 30 },
      issueFilterOptions,
      overviewStatus: "ready",
      issuesStatus: "ready",
      canEdit: false,
      ...overrides,
    },
    global: {
      provide: {
        _live_vue: live,
      },
    },
  });

  return { live, wrapper };
}

describe("SheetDashboard health", () => {
  it("preserves redirect navigation and forwards table sorting to LiveView", async () => {
    const { live, wrapper } = mountDashboard();
    const rowLink = wrapper.get('a[href="/workspaces/ws/projects/story/sheets/1"]');

    expect(rowLink.attributes("data-phx-link")).toBe("redirect");
    await wrapper.findAll("thead button")[1].trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "sort_sheets",
      { column: "block_count" },
      undefined,
    );
  });

  it("wires the row delete action to the exact LiveView event pair", async () => {
    const { live, wrapper } = mountDashboard({ canEdit: true });
    const trigger = wrapper.get('[data-slot="dropdown-menu-trigger"]');

    expect(trigger.attributes("aria-label")).toBe("Sheet actions");
    expect(trigger.attributes("title")).toBe("Sheet actions");

    await trigger.trigger("click");
    wrapper.getComponent(DropdownMenuItem).vm.$emit("select");

    expect(live.pushEvent).toHaveBeenNthCalledWith(
      1,
      "set_pending_delete_sheet",
      { id: 1 },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(2, "confirm_delete_sheet", {}, undefined);
  });

  it("forwards complete faceted counts to the shared issue filters", () => {
    const { wrapper } = mountDashboard();

    expect(wrapper.getComponent(DashboardIssueFilters).props("options")).toEqual(
      issueFilterOptions,
    );
  });

  it("marks issue filters busy without disabling them during a background refresh", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "refreshing" });

    expect(wrapper.getComponent(DashboardIssueFilters).props("busy")).toBe(true);
  });

  it("renders canonical severities and the shared health translations", () => {
    const { wrapper } = mountDashboard();
    const error = wrapper.get('a[data-severity="error"]');
    const warning = wrapper.get('a[data-severity="warning"]');
    const info = wrapper.get('a[data-severity="info"]');

    expect(error.get('[data-testid="dashboard-issue-error-icon"]').classes()).toContain(
      "text-red-500",
    );
    expect(warning.get('[data-testid="dashboard-issue-warning-icon"]').classes()).toContain(
      "text-yellow-500",
    );
    expect(info.get('[data-testid="dashboard-issue-info-icon"]').classes()).toContain(
      "text-blue-400",
    );
    expect(error.get(".sr-only").text()).toBe("Error:");
    expect(warning.get(".sr-only").text()).toBe("Warning:");
    expect(info.get(".sr-only").text()).toBe("Information:");

    expect(error.text()).toContain("Hero · The sheet has no shortcut");
    expect(warning.text()).toContain("Hero · Biography · This required block is empty");
    expect(info.text()).toContain("Empty Sheet · The sheet has no blocks or child sheets");
  });

  it("keeps loaded issues visible while the independent overview is loading", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ overviewStatus: "loading", issuesStatus: "ready" });

    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);
    expect(
      wrapper.getComponent(DashboardIssueFilters).props("codeLabel")!("missing_sheet_shortcut"),
    ).toBe("Missing sheet shortcut");
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
    expect(wrapper.text()).not.toContain("No sheets yet");

    await wrapper.get('[data-testid="dashboard-overview-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("keeps overview content under a persistent stale warning and retries only it", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({ overviewStatus: "stale" });

    const stale = wrapper.get('[data-testid="dashboard-overview-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded data");
    expect(wrapper.find('a[href="/workspaces/ws/projects/story/sheets/1"]').exists()).toBe(true);

    await wrapper.get('[data-testid="dashboard-overview-stale-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("announces the independent issues loading state", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "loading" });

    const status = wrapper.get('[data-testid="sheet-issues-loading"]');
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

    expect(wrapper.get('[data-testid="sheet-issues-error"]').attributes("role")).toBe("alert");
    expect(wrapper.find('a[href="/workspaces/ws/projects/story/sheets/1"]').exists()).toBe(true);

    await wrapper.get('[data-testid="sheet-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("preserves issues under a persistent stale warning and offers retry", async () => {
    const { live, wrapper } = mountDashboard();

    await wrapper.setProps({ issuesStatus: "stale" });

    const stale = wrapper.get('[data-testid="sheet-issues-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded results");
    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);

    await wrapper.get('[data-testid="sheet-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("keeps the stale warning without showing filters or an empty-filter state when no results exist", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({
      issuesStatus: "stale",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.find('[data-testid="sheet-issues-stale"]').exists()).toBe(true);
    expect(wrapper.findComponent(DashboardIssueFilters).exists()).toBe(false);
    expect(wrapper.find('[data-testid="dashboard-issue-list"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="dashboard-issues-empty-filter"]').exists()).toBe(false);
  });

  it("does not reveal an empty issues section during a background refresh", async () => {
    const { wrapper } = mountDashboard();

    await wrapper.setProps({
      issuesStatus: "refreshing",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.find('[data-testid="sheet-dashboard-issues"]').exists()).toBe(false);
  });

  it("forwards issue filters and pagination through their independent events", () => {
    const { live, wrapper } = mountDashboard();

    wrapper
      .getComponent(DashboardIssueFilters)
      .vm.$emit("change", { filter: "severity", value: "warning" });

    const paginators = wrapper.findAllComponents(DashboardPagination);
    expect(paginators).toHaveLength(2);
    paginators.at(-1)?.vm.$emit("page", 2);

    expect(live.pushEvent).toHaveBeenCalledWith(
      "filter_sheet_issues",
      {
        filter: "severity",
        value: "warning",
      },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenCalledWith("page_sheet_issues", { page: 2 }, undefined);
  });
});
