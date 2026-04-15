<script setup lang="ts">
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { type CellValue, SelectOption, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "@composables/useLive.ts";
import { computed } from "vue";
import { Checkbox } from "@components/ui/checkbox";
import { Badge } from "@components/ui/badge";
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

const options = computed<SelectOption[]>(() => column.config?.options || []);
const value = computed<CellValue>(() => getCellValue(row, column));

const selectedKeys = computed<string[]>(() =>
  Array.isArray(value.value) ? (value.value as string[]) : [],
);

const selectedOptions = computed<SelectOption[]>(() =>
  selectedKeys.value
    .map((key) => options.value.find((o) => o.key === key))
    .filter((o): o is SelectOption => !!o),
);

function optionLabel(opt: SelectOption): string {
  return opt.value || opt.key;
}

function toggleMultiSelectCell(key: string): void {
  live.pushEvent("toggle_table_cell_multi_select", {
    "row-id": row.id,
    "column-slug": column.slug,
    key,
  });
}
</script>

<template>
  <div v-if="canEdit" class="absolute inset-0">
    <Popover>
      <PopoverTrigger as-child>
        <button
          class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer bg-card/40 hover:bg-card/50"
        >
          <div v-if="selectedOptions.length" class="flex flex-wrap gap-1">
            <Badge v-for="opt in selectedOptions" :key="opt.key" variant="secondary">
              {{ optionLabel(opt) }}
            </Badge>
          </div>
          <span v-else class="text-muted-foreground/40 truncate">Select...</span>
        </button>
      </PopoverTrigger>

      <PopoverContent align="start" class="w-52 p-1">
        <div class="max-h-48 overflow-y-auto">
          <div v-if="options.length === 0" class="text-muted-foreground text-sm p-2">
            No options available
          </div>
          <button
            v-for="opt in options"
            :key="opt.key"
            type="button"
            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors"
            @click="toggleMultiSelectCell(opt.key)"
          >
            <Checkbox :model-value="selectedKeys.includes(opt.key)" class="pointer-events-none" />
            {{ opt.value }}
          </button>
        </div>
      </PopoverContent>
    </Popover>
  </div>

  <div v-else class="px-2 py-1">
    <div v-if="selectedOptions.length" class="flex flex-wrap gap-1">
      <Badge v-for="opt in selectedOptions" :key="opt.key" variant="secondary" class="text-[10px]">
        {{ opt.value }}
      </Badge>
    </div>
    <span v-else class="text-muted-foreground/40 text-sm">\u2014</span>
  </div>
</template>
