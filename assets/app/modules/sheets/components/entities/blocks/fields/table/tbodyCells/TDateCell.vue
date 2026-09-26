<script setup lang="ts">
import { type CellValue, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "../../../../../../../../shared/composables/useLive.ts";
import { getCellValue } from "@modules/sheets/components/entities/blocks/fields/table/tbodyCells/get-cell-value-helpers.ts";
import { useI18n } from "vue-i18n";
import { formatDate } from "@shared/utils/date-utils";

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
const { locale } = useI18n();

function displayDate(val: CellValue): string {
  return formatDate(val ? String(val) : null, locale.value, "dateLong") || "\u2014";
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
      {{ displayDate(getCellValue(row, column)) }}
    </span>
  </div>
</template>

<style scoped></style>
