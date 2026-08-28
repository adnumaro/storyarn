<script setup lang="ts">
import HealthStatusPopover from "@components/health/HealthStatusPopover.vue";
import { useLive } from "@shared/composables/useLive.ts";
import type {
  FlowHealth,
  FlowHealthItem,
  FlowHealthSeverity,
  FlowHealthStatusItem,
} from "@modules/flows/types/health";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: FlowHealth;
}>();

const live = useLive();

// A flow-level finding (missing entry, no exit) has nowhere to jump to; only
// node-scoped ones are navigable.
function canNavigate(item: FlowHealthStatusItem): boolean {
  const flowItem = item as FlowHealthItem;
  return flowItem.entityType !== "flow" && flowItem.entityId != null;
}

function itemKey(item: FlowHealthStatusItem, index: number, severity: FlowHealthSeverity): string {
  const flowItem = item as FlowHealthItem;
  return `${severity}-${flowItem.entityType}-${flowItem.entityId ?? index}`;
}

function itemDataAttributes(item: FlowHealthStatusItem) {
  const flowItem = item as FlowHealthItem;

  return {
    "data-health-entity-type": flowItem.entityType,
    "data-health-entity-id": flowItem.entityId,
  };
}

function navigateToFinding(item: FlowHealthStatusItem): void {
  const flowItem = item as FlowHealthItem;
  if (!canNavigate(flowItem)) return;

  live.pushEvent("navigate_to_node", { id: flowItem.entityId });
}
</script>

<template>
  <HealthStatusPopover
    :health="health"
    translation-prefix="flows.health"
    test-id-prefix="flow"
    :can-navigate="canNavigate"
    :item-key="itemKey"
    :item-data-attributes="itemDataAttributes"
    @navigate="navigateToFinding"
  />
</template>
