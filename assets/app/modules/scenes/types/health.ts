import type {
  HealthStatus,
  HealthStatusDetails,
  HealthStatusItem,
  HealthStatusReason,
  HealthStatusSeverity,
} from "@shared/types/health";

export type SceneHealthDetails = HealthStatusDetails;
export type SceneHealthReason = HealthStatusReason;
export type SceneHealthSeverity = HealthStatusSeverity;

export interface SceneHealthItem extends HealthStatusItem {
  entityType: string;
  entityId: number | string | null;
}

export type SceneHealth = HealthStatus<SceneHealthItem>;
