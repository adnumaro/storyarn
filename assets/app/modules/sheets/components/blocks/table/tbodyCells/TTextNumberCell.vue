<script setup lang="ts">
import { CellValue, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "../../../../../../shared/composables/useLive.ts";
import { nextTick, ref } from "vue";
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

const editingCell = ref<{ rowId: number | string; colSlug: string } | null>(null);
const editingCellValue = ref("");
const cellInput = ref<HTMLInputElement | null>(null);

interface NumberInputAttrs {
  min?: number;
  max?: number;
  step: number | string;
}

function inputAttrs(column: TableColumn): NumberInputAttrs | Record<string, never> {
  if (column.type !== "number") {
    return {};
  }
  const config = column.config || {};
  const attrs: NumberInputAttrs = { step: config.step || "any" };
  if (config.min != null) {
    attrs.min = config.min;
  }
  if (config.max != null) {
    attrs.max = config.max;
  }
  return attrs;
}

function startEditCell(row: TableRow, col: TableColumn): void {
  if (!canEdit) {
    return;
  }
  editingCell.value = { rowId: row.id, colSlug: col.slug };
  editingCellValue.value = String(row.cells?.[col.slug] ?? "");
  nextTick(() => cellInput.value?.focus());
}

function isCellEditing(row: TableRow, col: TableColumn): boolean {
  return editingCell.value?.rowId === row.id && editingCell.value?.colSlug === col.slug;
}

function displayValue(value: CellValue, fallback: string): string {
  if (value == null || value === "") {
    return fallback;
  }
  return String(value);
}

function saveCell(row: TableRow, col: TableColumn): void {
  editingCell.value = null;
  live.pushEvent("update_table_cell", {
    "row-id": row.id,
    "column-slug": col.slug,
    value: editingCellValue.value,
    type: col.type,
  });
}
</script>

<template>
  <template v-if="canEdit">
    <template v-if="isCellEditing(row, column)">
      <input
        ref="cellInput"
        v-model="editingCellValue"
        :type="column.type === 'number' ? 'number' : 'text'"
        v-bind="inputAttrs(column)"
        class="absolute inset-0 px-2 text-sm bg-background/20 hover:bg-background/25 border-0 rounded-none outline-none"
        @blur="saveCell(row, column)"
        @keydown.enter.prevent="saveCell(row, column)"
      />
    </template>
    <div
      v-else
      class="absolute inset-0 px-2 flex items-center text-sm cursor-text"
      @click="startEditCell(row, column)"
    >
      {{ displayValue(getCellValue(row, column), "") }}
    </div>
  </template>
  <div v-else class="px-2 py-1">
    <span
      :class="
        !getCellValue(row, column) && getCellValue(row, column) !== 0 && 'text-muted-foreground/40'
      "
      class="text-sm"
    >
      {{ displayValue(getCellValue(row, column), column.type === "number" ? "0" : "\u2014") }}
    </span>
  </div>
</template>

<style scoped></style>
