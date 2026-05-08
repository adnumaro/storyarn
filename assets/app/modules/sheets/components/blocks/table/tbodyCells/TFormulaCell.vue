<script setup lang="ts">
import { Sigma } from "lucide-vue-next";
import { CellValue, FormulaCellValue, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "../../../../../../shared/composables/useLive.ts";

const {
  blockId,
  column,
  row,
  canEdit = false,
} = defineProps<{
  blockId: number | string;
  column: TableColumn;
  row: TableRow;
  canEdit?: boolean;
}>();

const live = useLive();

function isFormulaCell(cell: CellValue | undefined): cell is FormulaCellValue {
  return typeof cell === "object" && cell !== null && !Array.isArray(cell);
}

function getFormulaDisplay(row: TableRow, column: TableColumn): string {
  const cell = row.cells?.[column.slug];
  if (cell == null) {
    return "\u2014";
  }
  if (isFormulaCell(cell)) {
    // __result is injected by compute_formulas on the server
    if (cell.__result !== undefined) {
      return cell.__result != null ? String(cell.__result) : "\u2014";
    }
    // Has expression but no computed result yet
    return "\u2014";
  }
  return cell !== "" ? String(cell) : "\u2014";
}

function getFormulaExpression(row: TableRow, column: TableColumn): string {
  const cell = row.cells?.[column.slug];
  if (isFormulaCell(cell) && cell.expression) {
    return cell.expression;
  }
  return "";
}

function openFormulaSidebar() {
  live.pushEvent("open_formula_sidebar", {
    "row-id": row.id,
    "column-slug": column.slug,
    "block-id": blockId,
  });
}
</script>

<template>
  <button
    v-if="canEdit"
    type="button"
    class="absolute inset-0 px-2 flex items-center gap-1.5 text-sm cursor-pointer text-left bg-background/20 hover:bg-background/25"
    @click="openFormulaSidebar"
  >
    <Sigma class="size-3 opacity-70 shrink-0" />
    <span :class="getFormulaDisplay(row, column) === '\u2014' && 'text-foreground/70 italic'">
      {{ getFormulaDisplay(row, column) }}
    </span>
  </button>
  <div v-else class="px-2 py-1">
    <span class="text-sm flex items-center gap-1">
      <Sigma class="size-3 opacity-30 shrink-0" />
      <template v-if="getFormulaDisplay(row, column) !== '\u2014'">
        {{ getFormulaDisplay(row, column) }}
      </template>
      <span
        v-else
        :class="
          getFormulaExpression(row, column)
            ? 'font-mono text-info/70 text-xs'
            : 'text-muted-foreground/40'
        "
      >
        {{ getFormulaExpression(row, column) || "\u2014" }}
      </span>
    </span>
  </div>
</template>

<style scoped></style>
