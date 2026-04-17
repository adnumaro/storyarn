<script setup lang="ts">
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { Check } from "lucide-vue-next";
import { CellValue, SelectOption, TableColumn, TableRow } from "@modules/sheets/types.ts";
import { useLive } from "@composables/useLive.ts";
import { computed } from "vue";
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

function optionLabel(opt: SelectOption): string {
  return opt.value || opt.key;
}

const selectedLabel = computed<string | null>(() => {
  if (!value.value) return null;
  const opt = options.value.find((o) => o.key === value.value);
  return opt ? optionLabel(opt) : null;
});

function selectCell(key: string): void {
  live.pushEvent("select_table_cell", {
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
          <span v-if="selectedLabel" class="truncate">{{ selectedLabel }}</span>
          <span v-else class="text-muted-foreground/40 truncate">{{
            $t("sheets.select_block.placeholder")
          }}</span>
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" class="w-52 p-1">
        <div class="max-h-48 overflow-y-auto">
          <div v-if="options.length === 0" class="text-muted-foreground text-sm p-2">
            {{ $t("sheets.select_block.no_options") }}
          </div>
          <template v-else>
            <button
              type="button"
              class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors"
              @click="selectCell('')"
            >
              <span class="text-muted-foreground">{{ $t("sheets.select_block.none") }}</span>
            </button>
            <button
              v-for="opt in options"
              :key="opt.key"
              type="button"
              class="flex items-center justify-between gap-2 w-full px-2 py-1.5 text-sm rounded hover:bg-accent transition-colors"
              @click="selectCell(opt.key)"
            >
              {{ optionLabel(opt) }}
              <Check v-if="value === opt.key" class="h-4 w-4 opacity-50" />
            </button>
          </template>
        </div>
      </PopoverContent>
    </Popover>
  </div>
  <div v-else class="px-2 py-1">
    <span :class="!selectedLabel && 'text-muted-foreground/40'" class="text-sm">
      {{ selectedLabel || "\u2014" }}
    </span>
  </div>
</template>
