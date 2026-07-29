<script setup lang="ts">
import HealthStatusPopover from "@components/health/HealthStatusPopover.vue";
import type { HealthStatusItem, HealthStatusSeverity } from "@shared/types/health";
import { highlightSheetLocation } from "@modules/sheets/composables/useSheetHighlight";
import type { SheetHealth, SheetHealthItem } from "@modules/sheets/types";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: SheetHealth;
}>();

function canNavigate(item: HealthStatusItem): boolean {
  return (item as SheetHealthItem).blockId != null;
}

function itemKey(item: HealthStatusItem, index: number, severity: HealthStatusSeverity): string {
  const sheetItem = item as SheetHealthItem;
  return `${severity}-${sheetItem.blockId ?? "sheet"}-${sheetItem.rowId ?? index}-${sheetItem.columnId ?? index}`;
}

function itemDataAttributes(item: HealthStatusItem) {
  const sheetItem = item as SheetHealthItem;

  return {
    "data-health-block-id": sheetItem.blockId,
    "data-health-row-id": sheetItem.rowId,
    "data-health-column-id": sheetItem.columnId,
  };
}

function navigateToFinding(item: HealthStatusItem): void {
  const sheetItem = item as SheetHealthItem;
  if (sheetItem.blockId == null) return;

  highlightSheetLocation({
    blockId: sheetItem.blockId,
    rowId: sheetItem.rowId,
    columnId: sheetItem.columnId,
  });
}
</script>

<template>
  <HealthStatusPopover
    :health="health"
    translation-prefix="sheets.health"
    test-id-prefix="sheet"
    :can-navigate="canNavigate"
    :item-key="itemKey"
    :item-data-attributes="itemDataAttributes"
    @navigate="navigateToFinding"
  />
</template>
