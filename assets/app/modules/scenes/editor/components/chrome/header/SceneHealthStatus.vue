<script setup lang="ts">
import HealthStatusPopover from "@components/health/HealthStatusPopover.vue";
import { useLive } from "@shared/composables/useLive.ts";
import type { HealthStatusItem, HealthStatusSeverity } from "@shared/types/health";
import type { SceneHealth, SceneHealthItem } from "@modules/scenes/types/health";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: SceneHealth;
}>();

const live = useLive();

function canNavigate(item: HealthStatusItem): boolean {
  const sceneItem = item as SceneHealthItem;
  return (
    ["pin", "zone", "connection", "annotation"].includes(sceneItem.entityType) &&
    sceneItem.entityId != null
  );
}

function itemKey(item: HealthStatusItem, index: number, severity: HealthStatusSeverity): string {
  const sceneItem = item as SceneHealthItem;
  return `${severity}-${sceneItem.entityType}-${sceneItem.entityId ?? index}`;
}

function itemDataAttributes(item: HealthStatusItem) {
  const sceneItem = item as SceneHealthItem;

  return {
    "data-health-entity-type": sceneItem.entityType,
    "data-health-entity-id": sceneItem.entityId,
  };
}

function navigateToFinding(item: HealthStatusItem): void {
  const sceneItem = item as SceneHealthItem;
  if (!canNavigate(sceneItem)) return;

  live.pushEvent("focus_search_result", {
    type: sceneItem.entityType,
    id: sceneItem.entityId,
  });
}
</script>

<template>
  <HealthStatusPopover
    :health="health"
    translation-prefix="scenes.health"
    test-id-prefix="scene"
    :can-navigate="canNavigate"
    :item-key="itemKey"
    :item-data-attributes="itemDataAttributes"
    @navigate="navigateToFinding"
  />
</template>
