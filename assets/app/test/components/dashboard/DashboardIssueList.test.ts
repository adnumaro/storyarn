import { mount } from "@vue/test-utils";
import { h } from "vue";
import { describe, expect, it } from "vitest";
import DashboardIssueList from "../../../components/dashboard/DashboardIssueList.vue";
import type {
  DashboardIssueListItem,
  DashboardPagination,
} from "../../../components/dashboard/types";

interface TestIssue extends DashboardIssueListItem {
  description: string;
}

const issues: TestIssue[] = [
  {
    id: "error-1",
    href: "/flows/1",
    severity: "error",
    label: "Opening · Dialogue #1",
    description: "Missing dialogue character",
  },
  {
    id: "warning-1",
    href: "/flows/2",
    severity: "warning",
    label: "Credits · Hub #2",
    description: "No outgoing connection",
  },
  {
    id: "info-1",
    href: "/flows/3",
    severity: "info",
    label: "Epilogue · Dialogue #3",
    description: "Optional localization is missing",
  },
];

const pagination: DashboardPagination = {
  page: 1,
  totalPages: 2,
  total: issues.length,
};

function mountIssueList(
  options: {
    issues?: TestIssue[];
    pagination?: DashboardPagination;
  } = {},
) {
  return mount(DashboardIssueList, {
    props: {
      issues: options.issues ?? issues,
      pagination: options.pagination ?? pagination,
    },
    slots: {
      description: ({ issue }: { issue: DashboardIssueListItem }) => {
        const testIssue = issue as TestIssue;

        return h(
          "span",
          { "data-testid": `issue-description-${testIssue.id}` },
          testIssue.description,
        );
      },
    },
  });
}

describe("DashboardIssueList", () => {
  it("renders issue navigation and the domain-specific description slot", () => {
    const wrapper = mountIssueList();
    const links = wrapper.get('[data-testid="dashboard-issue-list"]').findAll("a");

    expect(links).toHaveLength(3);
    expect(links.map((link) => link.attributes("href"))).toEqual([
      "/flows/1",
      "/flows/2",
      "/flows/3",
    ]);
    expect(links.map((link) => link.attributes("data-severity"))).toEqual([
      "error",
      "warning",
      "info",
    ]);

    for (const link of links) {
      expect(link.attributes("data-phx-link")).toBe("redirect");
      expect(link.attributes("data-phx-link-state")).toBe("push");
    }

    expect(wrapper.get('[data-testid="issue-description-error-1"]').text()).toBe(
      "Missing dialogue character",
    );
    expect(wrapper.get('[data-testid="issue-description-warning-1"]').text()).toBe(
      "No outgoing connection",
    );
    expect(wrapper.get('[data-testid="issue-description-info-1"]').text()).toBe(
      "Optional localization is missing",
    );
    expect(links[0].text()).toContain("Opening · Dialogue #1");
  });

  it("gives every severity a hidden text label and a decorative icon", () => {
    const wrapper = mountIssueList();
    const links = wrapper.get('[data-testid="dashboard-issue-list"]').findAll("a");

    expect(links.map((link) => link.get(".sr-only").text())).toEqual([
      "Error:",
      "Warning:",
      "Information:",
    ]);

    for (const testId of [
      "dashboard-issue-error-icon",
      "dashboard-issue-warning-icon",
      "dashboard-issue-info-icon",
    ]) {
      const icon = wrapper.get(`[data-testid="${testId}"]`);

      expect(icon.element.tagName).toBe("svg");
      expect(icon.attributes("aria-hidden")).toBe("true");
    }

    expect(links[0].find('[data-testid="dashboard-issue-warning-icon"]').exists()).toBe(false);
    expect(links[1].find('[data-testid="dashboard-issue-info-icon"]').exists()).toBe(false);
    expect(links[2].find('[data-testid="dashboard-issue-error-icon"]').exists()).toBe(false);
  });

  it("renders issue totals and forwards page changes", async () => {
    const wrapper = mountIssueList();

    expect(wrapper.get('[data-testid="dashboard-pagination-total"]').text()).toBe("3 issues");

    await wrapper.get('[data-testid="dashboard-pagination-next"]').trigger("click");

    expect(wrapper.emitted("page")).toEqual([[2]]);
  });

  it("renders the translated empty state without an irrelevant paginator", () => {
    const wrapper = mountIssueList({
      issues: [],
      pagination: { page: 1, totalPages: 1, total: 0 },
    });

    expect(wrapper.find('[data-testid="dashboard-issue-list"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="dashboard-issues-empty-filter"]').text()).toBe(
      "No issues match these filters.",
    );
    expect(wrapper.find('[data-testid="dashboard-pagination"]').exists()).toBe(false);
  });
});
