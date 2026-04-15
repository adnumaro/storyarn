<script setup lang="ts">
import { Popover, PopoverContent, PopoverTrigger } from '@components/ui/popover'
import { Check, X } from 'lucide-vue-next'
import { CellValue, SelectOption, TableColumn, TableRow } from '@modules/sheets/types.ts'
import { useLive } from '@composables/useLive.ts'
import { ref } from 'vue'
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

function selectCell(row: TableRow, col: TableColumn, key: string): void {
  live.pushEvent("select_table_cell", {
    "row-id": row.id,
    "column-slug": col.slug,
    key,
  });
}

function findOptionLabel(options: SelectOption[], key: CellValue): string | null {
  if (!key) {
    return null;
  }
  const opt = options.find((o) => o.key === key);
  return opt?.value || null;
}

function addCellOption(col: TableColumn, row: TableRow): void {
  const label = selectSearch.value.trim();
  if (!label) {
    return;
  }
  live.pushEvent("add_table_cell_option", {
    "column-id": col.id,
    "row-id": row.id,
    "column-slug": col.slug,
    value: label,
  });
  selectSearch.value = "";
}

function filteredOptions(col: TableColumn): SelectOption[] {
  const options = col.config?.options || [];
  const q = selectSearch.value.toLowerCase();
  if (!q) {
    return options;
  }
  return options.filter((o) => (o.value || "").toLowerCase().includes(q));
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
          <span
            v-if="findOptionLabel(column.config?.options || [], getCellValue(row, column))"
            class="truncate"
          >
            {{ findOptionLabel(column.config?.options || [], getCellValue(row, column)) }}
          </span>
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
            v-if="getCellValue(row, column)"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-xs text-muted-foreground hover:bg-accent rounded"
            @click="selectCell(row, column, '')"
          >
            <X class="size-3" />
            Clear
          </button>
          <button
            v-for="opt in filteredOptions(column)"
            :key="opt.key"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded"
            :class="getCellValue(row, column) === opt.key && 'bg-primary/10 text-primary'"
            @click="selectCell(row, column, opt.key)"
          >
            {{ opt.value }}
            <Check
              v-if="getCellValue(row, column) === opt.key"
              class="size-3 ml-auto opacity-60"
            />
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
    <span
      :class="
        !findOptionLabel(column.config?.options || [], getCellValue(row, column)) &&
        'text-muted-foreground/40'
      "
      class="text-sm"
    >
      {{ findOptionLabel(column.config?.options || [], getCellValue(row, column)) || "\u2014" }}
    </span>
  </div>
</template>

<style scoped>

</style>