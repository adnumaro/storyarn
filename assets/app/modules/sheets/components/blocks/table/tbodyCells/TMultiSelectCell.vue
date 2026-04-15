<script setup lang="ts">
import { Popover, PopoverContent, PopoverTrigger } from '@components/ui/popover'
import { type CellValue, SelectOption, TableColumn, TableRow } from '@modules/sheets/types.ts'
import { useLive } from '@composables/useLive.ts'
import { ref } from 'vue'
import { Checkbox } from '@components/ui/checkbox'
import { Badge } from '@components/ui/badge'
import { getCellValue } from '@modules/sheets/components/blocks/table/tbodyCells/get-cell-value-helpers.ts'

const {
  column,
  row,
  canEdit = false,
  canManage = false,
} = defineProps<{
  column: TableColumn;
  row: TableRow;
  canEdit?: boolean;
  canManage?: boolean;
}>();

const live = useLive();

const selectSearch = ref("");


function addCellOption(column: TableColumn, row: TableRow): void {
  const label = selectSearch.value.trim();
  if (!label) {
    return;
  }
  live.pushEvent("add_table_cell_option", {
    "column-id": column.id,
    "row-id": row.id,
    "column-slug": column.slug,
    value: label,
  });
  selectSearch.value = "";
}

function filteredOptions(column: TableColumn): SelectOption[] {
  const options = column.config?.options || [];
  const q = selectSearch.value.toLowerCase();
  if (!q) {
    return options;
  }
  return options.filter((o) => (o.value || "").toLowerCase().includes(q));
}

function toggleMultiSelectCell(row: TableRow, column: TableColumn, key: string): void {
  live.pushEvent("toggle_table_cell_multi_select", {
    "row-id": row.id,
    "column-slug": column.slug,
    key,
  });
}

function resolveMultiLabels(value: CellValue, options: SelectOption[]): string[] {
  if (!Array.isArray(value) || value.length === 0) {
    return [];
  }
  const map = Object.fromEntries(options.map((o) => [o.key, o.value]));
  return (value as string[]).map((k) => map[k] || k);
}
</script>

<template>
  <div v-if="canEdit" class="absolute inset-0">
    <Popover
      @update:open="
        (v) => {
          if (v) selectSearch = '';
        }
      "
    >
      <PopoverTrigger as-child>
        <button
          class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer bg-card/40 hover:bg-card/50"
        >
          <div
            v-if="resolveMultiLabels(getCellValue(row, column), column.config?.options || []).length"
            class="flex flex-wrap gap-1"
          >
            <Badge
              v-for="lbl in resolveMultiLabels(getCellValue(row, column), column.config?.options || [])"
              :key="lbl"
              class="text-[10px]"
            >
              {{ lbl }}
            </Badge>
          </div>
          <span v-else class="text-muted-foreground/40 truncate">
            Select...
          </span>
        </button>
      </PopoverTrigger>

      <PopoverContent align="start" class="w-52 p-0">
        <div class="p-2">
          <input
            v-model="selectSearch"
            placeholder="Search..."
            class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring"
          />
        </div>
        <div class="max-h-48 overflow-y-auto px-1 pb-1">
          <button
            v-for="opt in filteredOptions(column)"
            :key="opt.key"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded"
            :class="
              ((getCellValue(row, column) as string[]) || []).includes(opt.key) &&
              'bg-primary/10'
            "
            @click="toggleMultiSelectCell(row, column, opt.key)"
          >
            <Checkbox
              :checked="((getCellValue(row, column) as string[]) || []).includes(opt.key)"
              class="pointer-events-none"
            />
            {{ opt.value }}
          </button>
        </div>
        <div v-if="canManage" class="border-t border-border p-2">
          <input
            v-model="selectSearch"
            placeholder="+ New option"
            class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring"
            @keydown.enter.prevent="addCellOption(column, row)"
          />
        </div>
      </PopoverContent>
    </Popover>
  </div>

  <div v-else class="px-2 py-1">
    <div
      v-if="resolveMultiLabels(getCellValue(row, column), column.config?.options || []).length"
      class="flex flex-wrap gap-1"
    >
      <Badge
        v-for="lbl in resolveMultiLabels(getCellValue(row, column), column.config?.options || [])"
        :key="lbl"
        class="text-[10px]"
      >
        {{ lbl }}
      </Badge>
    </div>
    <span v-else class="text-muted-foreground/40 text-sm">
      \u2014
    </span>
  </div>
</template>

<style scoped>

</style>