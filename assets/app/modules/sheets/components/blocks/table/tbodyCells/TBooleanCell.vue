<script setup lang="ts">
import { Checkbox } from "@components/ui/checkbox";
import { Badge } from "@components/ui/badge";
import { TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "@composables/useLive.ts";
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

function toggleBoolean(row: TableRow, col: TableColumn): void {
  live.pushEvent("toggle_table_cell_boolean", {
    "row-id": row.id,
    "column-slug": col.slug,
  });
}
</script>

<template>
  <label v-if="canEdit" class="absolute inset-0 flex items-center justify-center cursor-pointer">
    <Checkbox
      :checked="getCellValue(row, column) === true"
      @update:checked="toggleBoolean(row, column)"
    />
  </label>
  <div v-else class="px-2 py-1">
    <Badge
      v-if="getCellValue(row, column) === true"
      class="text-[10px] bg-green-500/20 text-green-700 border-0"
    >
      Yes
    </Badge>
    <Badge
      v-else-if="getCellValue(row, column) === false"
      class="text-[10px] bg-red-500/20 text-red-700 border-0"
    >
      No
    </Badge>
    <span v-else class="text-muted-foreground/40 text-sm">\u2014</span>
  </div>
</template>

<style scoped></style>
