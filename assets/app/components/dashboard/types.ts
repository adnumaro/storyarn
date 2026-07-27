import type { HealthStatusSeverity } from "@shared/types/health";

export type DashboardLoadStatus = "loading" | "ready" | "refreshing" | "error" | "stale";

export interface DashboardPagination {
  page: number;
  totalPages: number;
  total: number;
}

export interface DashboardTablePagination extends DashboardPagination {
  sortBy: string;
  sortDir: "asc" | "desc";
}

export interface DashboardIssuePagination extends DashboardPagination {
  unfilteredTotal: number;
}

export interface DashboardTableRow {
  id: number | string;
}

export interface DashboardTableColumn {
  key: string;
  label: string;
  align: "left" | "right";
  hiddenClass?: string;
}

export interface DashboardIssueListItem {
  id: string;
  href: string;
  severity: HealthStatusSeverity;
  label: string;
}

export type DashboardIssueFilter = "severity" | "code" | "resource";

export interface DashboardIssueFilterValues {
  severity: string;
  code: string;
  resource: string;
}

export interface DashboardIssueCountOption {
  value: string;
  count: number;
}

export interface DashboardIssueResourceOption extends DashboardIssueCountOption {
  label: string;
}

export interface DashboardIssueFilterOptions {
  totals: Record<DashboardIssueFilter, number>;
  severities: DashboardIssueCountOption[];
  codes: DashboardIssueCountOption[];
  resources: DashboardIssueResourceOption[];
}

export function emptyDashboardIssueFilterOptions(): DashboardIssueFilterOptions {
  return {
    totals: { severity: 0, code: 0, resource: 0 },
    severities: [
      { value: "error", count: 0 },
      { value: "warning", count: 0 },
      { value: "info", count: 0 },
    ],
    codes: [],
    resources: [],
  };
}

export interface DashboardFilterPopoverOption {
  value: string;
  label: string;
  count: number;
  searchText?: string;
}
