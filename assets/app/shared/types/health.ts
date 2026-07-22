export type HealthStatusDetails = Record<
  string,
  string | number | boolean | string[] | number[] | null
>;

export interface HealthStatusReason {
  code: string;
  details?: HealthStatusDetails;
}

export type HealthStatusSeverity = "error" | "warning" | "info";

export interface HealthStatusItem {
  label: string;
  reasons: HealthStatusReason[];
}

export interface HealthStatus<TItem extends HealthStatusItem = HealthStatusItem> {
  errorItems: TItem[];
  warningItems: TItem[];
  infoItems: TItem[];
}
