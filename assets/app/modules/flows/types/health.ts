import type {
  HealthStatus,
  HealthStatusDetails,
  HealthStatusItem,
  HealthStatusReason,
  HealthStatusSeverity,
} from "@shared/types/health";

export type FlowHealthDetails = HealthStatusDetails;
export type FlowHealthReason = HealthStatusReason;
export type FlowHealthSeverity = HealthStatusSeverity;

export interface FlowHealthItem extends HealthStatusItem {
  entityType: string;
  entityId: number | string | null;
}

export type FlowHealth = HealthStatus<FlowHealthItem>;

/** One row of the flows dashboard "Problems" list. Mirrors sheets' `DashboardIssue`:
 * the server sends a CODE and the location label, Vue translates the code against
 * the same `flows.health.findings.*` catalog the editor popover uses. */
export interface FlowDashboardIssue {
  severity: FlowHealthSeverity;
  code: string;
  label: string;
  details?: FlowHealthDetails;
  href: string;
}
