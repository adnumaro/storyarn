import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import DashboardIssueFilters from "../../../../components/dashboard/DashboardIssueFilters.vue";
import DashboardPagination from "../../../../components/dashboard/DashboardPagination.vue";
import DropdownMenuItem from "../../../../components/ui/dropdown-menu/DropdownMenuItem.vue";
import SceneDashboard from "../../../../live/scene/dashboard/SceneDashboard.vue";
import { createMockLive } from "../../../setup";

type SceneDashboardProps = InstanceType<typeof SceneDashboard>["$props"];

const issues: NonNullable<SceneDashboardProps["issues"]> = [
  {
    id: "scene:connection:4:1",
    severity: "error",
    code: "invalid_connection_endpoint",
    label: "World · Road",
    scene_id: 1,
    entity_type: "connection",
    entity_id: 4,
    resource_id: 1,
    resource_label: "World",
    href: "/workspaces/ws/projects/story/scenes/1?highlight=connection:4",
  },
  {
    id: "scene:missing-background:1",
    severity: "warning",
    code: "missing_background",
    label: "World",
    scene_id: 1,
    entity_type: "scene",
    entity_id: 1,
    resource_id: 1,
    resource_label: "World",
    href: "/workspaces/ws/projects/story/scenes/1",
  },
  {
    id: "scene:empty:2",
    severity: "info",
    code: "empty_scene",
    label: "Empty World",
    scene_id: 2,
    entity_type: "scene",
    entity_id: 2,
    resource_id: 2,
    resource_label: "Empty World",
    href: "/workspaces/ws/projects/story/scenes/2",
  },
];

const issueFilterOptions = {
  totals: { severity: 3, code: 3, resource: 3 },
  severities: [
    { value: "error", count: 1 },
    { value: "warning", count: 1 },
    { value: "info", count: 1 },
  ],
  codes: [
    { value: "empty_scene", count: 1 },
    { value: "invalid_connection_endpoint", count: 1 },
    { value: "missing_background", count: 1 },
  ],
  resources: [
    { value: "2", label: "Empty World", count: 1 },
    { value: "1", label: "World", count: 2 },
  ],
};

function mountDashboard(overrides: Partial<SceneDashboardProps> = {}) {
  const live = createMockLive();

  const wrapper = mount(SceneDashboard, {
    props: {
      stats: {
        scene_count: 1,
        zone_count: 0,
        pin_count: 0,
        background_count: 0,
      },
      tableData: [],
      pagination: {
        sortBy: "name",
        sortDir: "asc",
        page: 1,
        totalPages: 1,
        total: 1,
      },
      issues,
      overviewStatus: "ready",
      issuesStatus: "ready",
      issuePagination: {
        page: 1,
        totalPages: 1,
        total: issues.length,
        unfilteredTotal: issues.length,
      },
      issueFilters: { severity: "all", code: "all", resource: "all" },
      issueFilterOptions,
      canEdit: false,
      ...overrides,
    },
    global: {
      provide: { _live_vue: live },
    },
  });

  return { live, wrapper };
}

describe("SceneDashboard health", () => {
  it("forwards complete faceted counts to the shared issue filters", () => {
    const { wrapper } = mountDashboard();

    expect(wrapper.getComponent(DashboardIssueFilters).props("options")).toEqual(
      issueFilterOptions,
    );
  });

  it("marks issue filters busy without disabling them during a background refresh", () => {
    const { wrapper } = mountDashboard({ issuesStatus: "refreshing" });

    expect(wrapper.getComponent({ name: "DashboardIssuesSection" }).props("testIdPrefix")).toBe(
      "scene",
    );
    expect(wrapper.getComponent(DashboardIssueFilters).props("busy")).toBe(true);
    expect(wrapper.get('[data-testid="scene-issues-refreshing"]').text()).toContain(
      "Updating issues",
    );
  });

  it("renders canonical severities, translations, and deep links", () => {
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

    expect(error.text()).toContain("World · Road · The connection has an invalid endpoint");
    expect(warning.text()).toContain("World · The scene has no background image");
    expect(info.text()).toContain("Empty World · The scene has no zones or pins");
    expect(error.attributes("href")).toContain("highlight=connection:4");
  });

  it("uses the canonical row link returned by the async overview", async () => {
    const href = "/workspaces/ws/projects/story/scenes/99";
    const { live, wrapper } = mountDashboard({
      tableData: [
        {
          id: 99,
          name: "Linked Scene",
          href,
          zone_count: 0,
          pin_count: 0,
          connection_count: 0,
          updated_at: "2026-07-26T12:00:00Z",
        },
      ],
    });

    const rowLink = wrapper.get(`a[href="${href}"]`);

    expect(rowLink.text()).toBe("Linked Scene");
    expect(rowLink.attributes("data-phx-link")).toBe("patch");
    await wrapper.findAll("thead button")[1].trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("sort_scenes", { column: "zone_count" }, undefined);
  });

  it("wires confirmed row deletion to the exact LiveView event pair", async () => {
    const row = {
      id: 99,
      name: "Doomed Scene",
      href: "/workspaces/ws/projects/story/scenes/99",
      zone_count: 0,
      pin_count: 0,
      connection_count: 0,
      updated_at: "2026-07-26T12:00:00Z",
    };
    const { live, wrapper } = mountDashboard({ canEdit: true, tableData: [row] });

    await wrapper.get('[data-slot="dropdown-menu-trigger"]').trigger("click");
    wrapper.getComponent(DropdownMenuItem).vm.$emit("select");
    await wrapper.vm.$nextTick();

    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    confirmation.vm.$emit("confirm");
    await wrapper.vm.$nextTick();

    expect(live.pushEvent).toHaveBeenNthCalledWith(
      1,
      "set_pending_delete_scene",
      { id: 99 },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenNthCalledWith(2, "confirm_delete_scene", {}, undefined);
  });

  it("keeps an open delete confirmation mounted when the overview becomes empty", async () => {
    const row = {
      id: 99,
      name: "Doomed Scene",
      href: "/workspaces/ws/projects/story/scenes/99",
      zone_count: 0,
      pin_count: 0,
      connection_count: 0,
      updated_at: "2026-07-26T12:00:00Z",
    };
    const { live, wrapper } = mountDashboard({ canEdit: true, tableData: [row] });

    await wrapper.get('[data-slot="dropdown-menu-trigger"]').trigger("click");
    wrapper.getComponent(DropdownMenuItem).vm.$emit("select");
    await wrapper.vm.$nextTick();

    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);

    await wrapper.setProps({
      tableData: [],
      pagination: {
        sortBy: "name",
        sortDir: "asc",
        page: 1,
        totalPages: 1,
        total: 0,
      },
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.getComponent(ConfirmDialog).props("open")).toBe(true);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("shows issue loading independently from the overview", () => {
    const { wrapper } = mountDashboard({ issuesStatus: "loading" });

    const status = wrapper.get('[data-testid="scene-issues-loading"]');
    expect(status.attributes("role")).toBe("status");
    expect(status.text()).toContain("Loading issues");
    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(false);
    expect(wrapper.text()).toContain("All Scenes");
  });

  it("keeps loaded issues visible while the independent overview is loading", () => {
    const { wrapper } = mountDashboard({ overviewStatus: "loading", issuesStatus: "ready" });

    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);
    expect(
      wrapper.getComponent(DashboardIssueFilters).props("codeLabel")!(
        "invalid_connection_endpoint",
      ),
    ).toBe("Invalid connection endpoint");
  });

  it("keeps overview content under a persistent stale warning and retries only it", async () => {
    const href = "/workspaces/ws/projects/story/scenes/99";
    const { live, wrapper } = mountDashboard({
      overviewStatus: "stale",
      tableData: [
        {
          id: 99,
          name: "Linked Scene",
          href,
          zone_count: 0,
          pin_count: 0,
          connection_count: 0,
          updated_at: "2026-07-26T12:00:00Z",
        },
      ],
    });

    const stale = wrapper.get('[data-testid="dashboard-overview-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded data");
    expect(wrapper.find(`a[href="${href}"]`).exists()).toBe(true);

    await wrapper.get('[data-testid="dashboard-overview-stale-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("shows an independent initial issues error with its own retry", async () => {
    const { live, wrapper } = mountDashboard({
      issuesStatus: "error",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.get('[data-testid="scene-issues-error"]').attributes("role")).toBe("alert");
    expect(wrapper.text()).toContain("All Scenes");

    await wrapper.get('[data-testid="scene-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
    expect(live.pushEvent).not.toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("preserves issues under a persistent stale warning and offers retry", async () => {
    const { live, wrapper } = mountDashboard({ issuesStatus: "stale" });

    const stale = wrapper.get('[data-testid="scene-issues-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.text()).toContain("Showing the last loaded results");
    expect(wrapper.find('a[data-severity="error"]').exists()).toBe(true);

    await wrapper.get('[data-testid="scene-issues-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_issues", {}, undefined);
  });

  it("keeps the stale warning without showing filters or an empty-filter state when no results exist", () => {
    const { wrapper } = mountDashboard({
      issuesStatus: "stale",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.find('[data-testid="scene-issues-stale"]').exists()).toBe(true);
    expect(wrapper.findComponent(DashboardIssueFilters).exists()).toBe(false);
    expect(wrapper.find('[data-testid="dashboard-issue-list"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="dashboard-issues-empty-filter"]').exists()).toBe(false);
  });

  it("does not reveal an empty issues section during a background refresh", () => {
    const { wrapper } = mountDashboard({
      issuesStatus: "refreshing",
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 0 },
    });

    expect(wrapper.find('[data-testid="scene-dashboard-issues"]').exists()).toBe(false);
  });

  it("shows an explicit initial error and retries the overview load", async () => {
    const { live, wrapper } = mountDashboard({
      overviewStatus: "error",
      pagination: { sortBy: "name", sortDir: "asc", page: 1, totalPages: 1, total: 0 },
    });

    expect(wrapper.get('[data-testid="dashboard-overview-error"]').attributes("role")).toBe(
      "alert",
    );
    expect(wrapper.text()).not.toContain("No scenes yet");

    await wrapper.get('[data-testid="dashboard-overview-retry"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("retry_dashboard_overview", {}, undefined);
  });

  it("forwards table pages, issue pages, and issue filters to LiveView", () => {
    const { live, wrapper } = mountDashboard({
      pagination: { sortBy: "name", sortDir: "asc", page: 1, totalPages: 2, total: 26 },
      issuePagination: { page: 1, totalPages: 2, total: 26, unfilteredTotal: 26 },
    });

    wrapper
      .getComponent(DashboardIssueFilters)
      .vm.$emit("change", { filter: "severity", value: "warning" });

    const paginations = wrapper.findAllComponents(DashboardPagination);
    expect(paginations).toHaveLength(2);
    paginations[0].vm.$emit("page", 2);
    paginations[1].vm.$emit("page", 2);

    expect(live.pushEvent).toHaveBeenCalledWith(
      "filter_scene_issues",
      {
        filter: "severity",
        value: "warning",
      },
      undefined,
    );
    expect(live.pushEvent).toHaveBeenCalledWith("page_scenes", { page: 2 }, undefined);
    expect(live.pushEvent).toHaveBeenCalledWith("page_scene_issues", { page: 2 }, undefined);
  });

  it("renders a no-matches state without hiding the active filters", () => {
    const { wrapper } = mountDashboard({
      issues: [],
      issuePagination: { page: 1, totalPages: 1, total: 0, unfilteredTotal: 3 },
      issueFilters: { severity: "error", code: "all", resource: "all" },
    });

    expect(wrapper.findComponent(DashboardIssueFilters).exists()).toBe(true);
    expect(wrapper.get('[data-testid="dashboard-issues-empty-filter"]').text()).toBe(
      "No issues match these filters.",
    );
  });

  it("keeps issue DOM identity when stable IDs are reordered", async () => {
    const { wrapper } = mountDashboard();
    const originalError = wrapper.get('a[data-severity="error"]').element;

    await wrapper.setProps({ issues: [...issues].reverse() });

    expect(wrapper.get('a[data-severity="error"]').element).toBe(originalError);
  });
});
