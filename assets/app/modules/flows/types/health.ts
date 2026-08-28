/**
 * Flow-owned health read model.
 *
 * Keep this structural at the presentation edge: generic health UI may render
 * it, but Flows does not compile against another context's model.
 */
export type FlowHealthDetails = Record<
  string,
  string | number | boolean | string[] | number[] | null
>;

export interface FlowHealthReason {
  code: string;
  details?: FlowHealthDetails;
}

export type FlowHealthSeverity = "error" | "warning" | "info";

export interface FlowHealthStatusItem {
  label: string;
  reasons: FlowHealthReason[];
}

export interface FlowHealthItem extends FlowHealthStatusItem {
  entityType: string;
  entityId: number | string | null;
}

export interface FlowHealth {
  errorItems: FlowHealthItem[];
  warningItems: FlowHealthItem[];
  infoItems: FlowHealthItem[];
}

/** One row of the flows dashboard "Problems" list. Mirrors sheets' `DashboardIssue`:
 * the server sends a CODE and the location label, Vue translates the code against
 * the same `flows.health.findings.*` catalog the editor popover uses. */
export interface FlowDashboardIssue {
  id: string;
  severity: FlowHealthSeverity;
  code: string;
  label: string;
  details?: FlowHealthDetails;
  href: string;
  flow_id: number | string;
  entity_type: string;
  entity_id: number | string | null;
  resource_id: number | string;
  resource_label: string;
}
