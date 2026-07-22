<script setup lang="ts">
import HealthStatusPopover from "@components/health/HealthStatusPopover.vue";
import type { HealthStatusItem, HealthStatusSeverity } from "@shared/types/health";
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

function selectorValue(value: number | string): string {
  return String(value).replaceAll('"', '\\"');
}

function findTarget(item: SheetHealthItem): HTMLElement | null {
  if (item.rowId != null && item.columnId != null) {
    const row = selectorValue(item.rowId);
    const column = selectorValue(item.columnId);
    const cell = document.querySelector<HTMLElement>(
      `[data-sheet-row-id="${row}"] [data-sheet-column-id="${column}"]`,
    );
    if (cell) return cell;
  }

  if (item.rowId != null) {
    const row = selectorValue(item.rowId);
    const rowElement = document.querySelector<HTMLElement>(`[data-sheet-row-id="${row}"]`);
    if (rowElement) return rowElement;
  }

  if (item.blockId == null) return null;
  return document.getElementById(`sheet-block-${item.blockId}`);
}

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
  const target = findTarget(item as SheetHealthItem);
  if (!target) return;

  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add("ring-2", "ring-primary", "ring-offset-2", "ring-offset-background");
  window.setTimeout(() => {
    target.classList.remove("ring-2", "ring-primary", "ring-offset-2", "ring-offset-background");
  }, 1600);
}
</script>

<template>
  <HealthStatusPopover
    :health="health"
    translation-prefix="sheets.health"
    test-id-prefix="sheet"
    root-class="pt-2"
    :can-navigate="canNavigate"
    :item-key="itemKey"
    :item-data-attributes="itemDataAttributes"
    @navigate="navigateToFinding"
  />
</template>
