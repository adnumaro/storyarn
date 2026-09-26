import type {
  HealthStatus,
  HealthStatusDetails,
  HealthStatusItem,
  HealthStatusSeverity,
} from "@shared/types/health";

export type SceneHealthDetails = HealthStatusDetails;
export type SceneHealthSeverity = HealthStatusSeverity;

export interface SceneHealthItem extends HealthStatusItem {
  entityType: string;
  entityId: number | string | null;
}

export type SceneHealth = HealthStatus<SceneHealthItem>;
