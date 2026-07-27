import { mount } from "@vue/test-utils";
import { h } from "vue";
import { describe, expect, it } from "vitest";
import DashboardIssueFilters from "../../../components/dashboard/DashboardIssueFilters.vue";
import DashboardIssuesSection from "../../../components/dashboard/DashboardIssuesSection.vue";
import type {
  DashboardIssueListItem,
  DashboardLoadStatus,
} from "../../../components/dashboard/types";

interface TestIssue extends DashboardIssueListItem {
  description: string;
}

const issue: TestIssue = {
  id: "warning-1",
  href: "/flows/1",
  severity: "warning",
  label: "Opening",
  description: "No outgoing connection",
};

const filterOptions = {
  totals: { severity: 1, code: 1, resource: 1 },
  severities: [
    { value: "error", count: 0 },
    { value: "warning", count: 1 },
    { value: "info", count: 0 },
  ],
  codes: [{ value: "no_outgoing_connection", count: 1 }],
  resources: [{ value: "1", label: "Opening", count: 1 }],
};

function mountSection(
  overrides: {
    status?: DashboardLoadStatus;
    issues?: TestIssue[];
    total?: number;
    unfilteredTotal?: number;
  } = {},
) {
  return mount(DashboardIssuesSection, {
    props: {
      title: "Problems",
      testIdPrefix: "flow",
      status: overrides.status ?? "ready",
      issues: overrides.issues ?? [issue],
      pagination: {
        page: 1,
        totalPages: 1,
        total: overrides.total ?? 1,
        unfilteredTotal: overrides.unfilteredTotal ?? 1,
      },
      filters: { severity: "all", code: "all", resource: "all" },
      filterOptions,
      allResourcesLabel: "All flows",
      codeLabel: (code: string) => `Code: ${code}`,
    },
    slots: {
      description: ({ issue: slotIssue }: { issue: DashboardIssueListItem }) =>
        h("span", (slotIssue as TestIssue).description),
    },
  });
}

describe("DashboardIssuesSection", () => {
  it("owns the accessible loading, error, and stale state contract", async () => {
    const wrapper = mountSection({ status: "loading", issues: [], total: 0, unfilteredTotal: 0 });

    const loading = wrapper.get('[data-testid="flow-issues-loading"]');
    expect(loading.attributes("role")).toBe("status");
    expect(loading.attributes("aria-live")).toBe("polite");
    expect(loading.text()).toContain("Loading issues");

    await wrapper.setProps({ status: "error" });

    expect(wrapper.get('[data-testid="flow-issues-error"]').attributes("role")).toBe("alert");
    await wrapper.get('[data-testid="flow-issues-retry"]').trigger("click");
    expect(wrapper.emitted("retry")).toEqual([[]]);

    await wrapper.setProps({ status: "stale" });

    const stale = wrapper.get('[data-testid="flow-issues-stale"]');
    expect(stale.attributes("role")).toBe("status");
    expect(stale.attributes("aria-live")).toBe("polite");
    expect(wrapper.findComponent(DashboardIssueFilters).exists()).toBe(false);
    expect(wrapper.find('[data-testid="dashboard-issues-empty-filter"]').exists()).toBe(false);
  });

  it("keeps loaded controls and results visible with a visible busy announcement while refreshing", async () => {
    const wrapper = mountSection();
    const originalIssue = wrapper.get('a[data-severity="warning"]').element;

    await wrapper.setProps({ status: "refreshing" });

    const section = wrapper.get('[data-testid="flow-dashboard-issues"]');
    const refreshing = wrapper.get('[data-testid="flow-issues-refreshing"]');

    expect(section.attributes("aria-busy")).toBe("true");
    expect(refreshing.attributes("role")).toBe("status");
    expect(refreshing.attributes("aria-live")).toBe("polite");
    expect(refreshing.text()).toContain("Updating issues");
    expect(wrapper.getComponent(DashboardIssueFilters).props("busy")).toBe(true);
    expect(wrapper.get('a[data-severity="warning"]').element).toBe(originalIssue);
  });

  it("shows no-match only when issues exist before applying filters", () => {
    const noIssues = mountSection({ issues: [], total: 0, unfilteredTotal: 0 });
    const noMatches = mountSection({ issues: [], total: 0, unfilteredTotal: 3 });

    expect(noIssues.find('[data-testid="flow-dashboard-issues"]').exists()).toBe(false);
    expect(noMatches.find('[data-testid="flow-dashboard-issues"]').exists()).toBe(true);
    expect(noMatches.findComponent(DashboardIssueFilters).exists()).toBe(true);
    expect(noMatches.get('[data-testid="dashboard-issues-empty-filter"]').text()).toBe(
      "No issues match these filters.",
    );
  });

  it("forwards filter and pagination events without changing their payloads", () => {
    const wrapper = mountSection();

    wrapper
      .getComponent(DashboardIssueFilters)
      .vm.$emit("change", { filter: "code", value: "no_outgoing_connection" });
    wrapper.getComponent({ name: "DashboardIssueList" }).vm.$emit("page", 2);

    expect(wrapper.emitted("filter")).toEqual([
      [{ filter: "code", value: "no_outgoing_connection" }],
    ]);
    expect(wrapper.emitted("page")).toEqual([[2]]);
  });
});
