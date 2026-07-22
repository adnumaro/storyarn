export type SceneHealthDetails = Record<
  string,
  string | number | boolean | string[] | number[] | null
>;

export interface SceneHealthReason {
  code: string;
  details?: SceneHealthDetails;
}

export type SceneHealthSeverity = "error" | "warning" | "info";

export interface SceneHealthItem {
  entityType: string;
  entityId: number | string | null;
  label: string;
  reasons: SceneHealthReason[];
}

export interface SceneHealth {
  errorItems: SceneHealthItem[];
  warningItems: SceneHealthItem[];
  infoItems: SceneHealthItem[];
}
