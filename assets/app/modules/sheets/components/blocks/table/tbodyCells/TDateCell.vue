<script setup lang="ts">
import { type CellValue, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "../../../../../../shared/composables/useLive.ts";
import { getCellValue } from "@modules/sheets/components/blocks/table/tbodyCells/get-cell-value-helpers.ts";

const {
  column,
  row,
  canEdit = false,
} = defineProps<{
  column: TableColumn;
  row: TableRow;
  canEdit?: boolean;
}>();

const live = useLive();

function formatDate(val: CellValue): string {
  if (!val) {
    return "\u2014";
  }
  try {
    const d = new Date(String(val) + "T00:00:00");
    return d.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  } catch {
    return String(val);
  }
}

function updateDate(row: TableRow, column: TableColumn, value: string): void {
  live.pushEvent("update_table_cell", {
    "row-id": row.id,
    "column-slug": column.slug,
    value,
    type: "date",
  });
}
</script>

<template>
  <input
    v-if="canEdit"
    type="date"
    :value="getCellValue(row, column) as string"
    class="absolute inset-0 px-2 text-sm bg-background/20 hover:bg-background/25 border-0 rounded-none outline-none"
    @change="(event) => updateDate(row, column, (event.target as HTMLInputElement).value)"
  />
  <div v-else class="px-2 py-1">
    <span :class="!getCellValue(row, column) && 'text-foreground/40'" class="text-sm">
      {{ formatDate(getCellValue(row, column)) }}
    </span>
  </div>
</template>

<style scoped></style>
