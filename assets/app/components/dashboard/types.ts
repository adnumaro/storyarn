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
