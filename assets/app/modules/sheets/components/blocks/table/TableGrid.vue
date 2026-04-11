<script setup lang="ts">
import { makeDroppable } from "@vue-dnd-kit/core";
import type { IDragEvent } from "@vue-dnd-kit/core";
import { Check, Plus, Sigma, X } from "lucide-vue-next";
import { nextTick, ref, useTemplateRef, watch } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Checkbox } from "@components/ui/checkbox/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { useLive } from "@composables/useLive";
import type {
  CellValue,
  FormulaCellValue,
  SelectOption,
  TableColumn,
  TableRow,
} from "../../../types";
import TableColumnHeader from "./TableColumnHeader.vue";
import TableDraggableRow from "./TableDraggableRow.vue";
import TableRowActions from "./TableRowActions.vue";
import { typeIcon } from "./table-config";

const {
  blockId,
  columns = [],
  rows = [],
  canEdit = false,
  canManage = false,
} = defineProps<{
  blockId: number | string;
  columns?: TableColumn[];
  rows?: TableRow[];
  canEdit?: boolean;
  // canManage: can modify structure (columns/rows). False for inherited (schema_locked) tables.
  canManage?: boolean;
}>();

const live = useLive();

// ══════════════════════════════════════════════════════════════
// Row reorder via vue-dnd-kit (canManage only)
// ══════════════════════════════════════════════════════════════
const rowGroup = `table-rows-${blockId}`;
const localRows = ref<TableRow[]>([...rows]);
watch(
  () => rows,
  (v) => {
    localRows.value = [...v];
  },
);

const tbodyRef = useTemplateRef("tbodyRef");
makeDroppable(
  tbodyRef,
  {
    groups: [rowGroup],
    events: {
      onDrop: (e: IDragEvent) => {
        const result = e.helpers.suggestSort("vertical");
        if (!result) return;
        localRows.value = result.sourceItems as TableRow[];
        const ids = localRows.value.map((r) => r.id);
        live.pushEvent("reorder_table_rows", {
          block_id: blockId,
          row_ids: ids,
        });
      },
    },
  },
  () => localRows.value,
);

// ══════════════════════════════════════════════════════════════
// Cell editing — text/number (canEdit)
// ══════════════════════════════════════════════════════════════
const editingCell = ref<{ rowId: number | string; colSlug: string } | null>(null);
const editingCellValue = ref("");
const cellInput = ref<HTMLInputElement | null>(null);

function startEditCell(row: TableRow, col: TableColumn): void {
  if (!canEdit) return;
  editingCell.value = { rowId: row.id, colSlug: col.slug };
  editingCellValue.value = String(row.cells?.[col.slug] ?? "");
  nextTick(() => cellInput.value?.focus());
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

function isCellEditing(row: TableRow, col: TableColumn): boolean {
  return editingCell.value?.rowId === row.id && editingCell.value?.colSlug === col.slug;
}

// ══════════════════════════════════════════════════════════════
// Boolean toggle (canEdit)
// ══════════════════════════════════════════════════════════════
function toggleBoolean(row: TableRow, col: TableColumn): void {
  live.pushEvent("toggle_table_cell_boolean", {
    "row-id": row.id,
    "column-slug": col.slug,
  });
}

// ══════════════════════════════════════════════════════════════
// Select / Multi-select cells (canEdit)
// ══════════════════════════════════════════════════════════════
const selectSearch = ref("");

function selectCell(row: TableRow, col: TableColumn, key: string): void {
  live.pushEvent("select_table_cell", {
    "row-id": row.id,
    "column-slug": col.slug,
    key,
  });
}

function toggleMultiSelectCell(row: TableRow, col: TableColumn, key: string): void {
  live.pushEvent("toggle_table_cell_multi_select", {
    "row-id": row.id,
    "column-slug": col.slug,
    key,
  });
}

function addCellOption(col: TableColumn, row: TableRow): void {
  const label = selectSearch.value.trim();
  if (!label) return;
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
  if (!q) return options;
  return options.filter((o) => (o.value || "").toLowerCase().includes(q));
}

// ══════════════════════════════════════════════════════════════
// Add column / row (canManage only)
// ══════════════════════════════════════════════════════════════
function addColumn(): void {
  live.pushEvent("add_table_column", { "block-id": blockId });
}

function addRow(): void {
  live.pushEvent("add_table_row", { "block-id": blockId });
}

// ══════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════
function getCellValue(row: TableRow, col: TableColumn): CellValue {
  return row.cells?.[col.slug] ?? "";
}

function isFormulaCell(cell: CellValue | undefined): cell is FormulaCellValue {
  return typeof cell === "object" && cell !== null && !Array.isArray(cell);
}

function getFormulaDisplay(row: TableRow, col: TableColumn): string {
  const cell = row.cells?.[col.slug];
  if (cell == null) return "\u2014";
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

function getFormulaExpression(row: TableRow, col: TableColumn): string {
  const cell = row.cells?.[col.slug];
  if (isFormulaCell(cell) && cell.expression) {
    return cell.expression;
  }
  return "";
}

function findOptionLabel(options: SelectOption[], key: CellValue): string | null {
  if (!key) return null;
  const opt = options.find((o) => o.key === key);
  return opt?.value || null;
}

function resolveMultiLabels(value: CellValue, options: SelectOption[]): string[] {
  if (!Array.isArray(value) || value.length === 0) return [];
  const map = Object.fromEntries(options.map((o) => [o.key, o.value]));
  return (value as string[]).map((k) => map[k] || k);
}

function formatDate(val: CellValue): string {
  if (!val) return "\u2014";
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

function displayValue(val: CellValue, fallback: string): string {
  if (val == null || val === "") return fallback;
  return String(val);
}

interface NumberInputAttrs {
  min?: number;
  max?: number;
  step: number | string;
}

function inputAttrs(col: TableColumn): NumberInputAttrs | Record<string, never> {
  if (col.type !== "number") return {};
  const c = col.config || {};
  const attrs: NumberInputAttrs = { step: c.step || "any" };
  if (c.min != null) attrs.min = c.min;
  if (c.max != null) attrs.max = c.max;
  return attrs;
}
</script>

<template>
  <div class="group/table w-full max-w-full" @click.stop>
    <div class="flex w-full max-w-full min-w-0 items-stretch gap-2">
      <!-- ═══ TABLE ═══ -->
      <div class="flex-1 min-w-0 max-w-full overflow-auto rounded-lg border border-border">
        <table
          class="min-w-full w-max text-sm [&_:is(th,td)]:border-r [&_:is(th,td)]:border-border [&_:is(th,td):last-child]:border-r-0"
          style="table-layout: fixed"
        >
          <colgroup>
            <col style="width: 8rem" />
            <col
              v-for="col in columns"
              :key="col.id"
              :style="{ width: (col.config?.width || 150) + 'px' }"
            />
          </colgroup>

          <!-- ═══ HEADER ═══ -->
          <thead>
            <tr
              class="bg-muted/50 border-b border-border [&>th:first-child]:rounded-tl-lg [&>th:last-child]:rounded-tr-lg"
            >
              <!-- Row label header (empty) -->
              <th class="font-medium text-muted-foreground/60 sticky left-0 z-10 bg-muted/50" />

              <!-- Column headers -->
              <th
                v-for="col in columns"
                :key="col.id"
                class="font-medium text-muted-foreground/70 relative overflow-hidden"
              >
                <TableColumnHeader :column="col" :columns="columns" :can-manage="canManage" />
              </th>
            </tr>
          </thead>

          <!-- ═══ BODY ═══ -->
          <tbody ref="tbodyRef">
            <TableDraggableRow
              v-for="(row, rowIdx) in localRows"
              :key="row.id"
              :index="rowIdx"
              :items="localRows"
              :group="rowGroup"
              v-slot="{ isDragOver }"
            >
              <!-- ══ Row label cell ══ -->
              <td class="sticky left-0 z-10 bg-card font-medium text-muted-foreground/60 text-sm">
                <TableRowActions :row="row" :rows="rows" :can-manage="canManage" />
              </td>

              <!-- ══ Data cells ══ -->
              <td v-for="col in columns" :key="col.id" class="p-0! relative h-1">
                <!-- ── Boolean ── -->
                <template v-if="col.type === 'boolean'">
                  <label
                    v-if="canEdit"
                    class="absolute inset-0 flex items-center justify-center cursor-pointer"
                  >
                    <Checkbox
                      :checked="getCellValue(row, col) === true"
                      @update:checked="toggleBoolean(row, col)"
                    />
                  </label>
                  <div v-else class="px-2 py-1">
                    <Badge
                      v-if="getCellValue(row, col) === true"
                      class="text-[10px] bg-green-500/20 text-green-700 border-0"
                      >Yes</Badge
                    >
                    <Badge
                      v-else-if="getCellValue(row, col) === false"
                      class="text-[10px] bg-red-500/20 text-red-700 border-0"
                      >No</Badge
                    >
                    <span v-else class="text-muted-foreground/40 text-sm">\u2014</span>
                  </div>
                </template>

                <!-- ── Select ── -->
                <template v-else-if="col.type === 'select'">
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
                          class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-muted/50"
                        >
                          <span
                            v-if="
                              findOptionLabel(col.config?.options || [], getCellValue(row, col))
                            "
                            class="truncate"
                            >{{
                              findOptionLabel(col.config?.options || [], getCellValue(row, col))
                            }}</span
                          >
                          <span v-else class="text-muted-foreground/40 truncate">Select...</span>
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
                            v-if="getCellValue(row, col)"
                            class="flex items-center gap-2 w-full px-2 py-1.5 text-xs text-muted-foreground hover:bg-accent rounded"
                            @click="selectCell(row, col, '')"
                          >
                            <X class="size-3" /> Clear
                          </button>
                          <button
                            v-for="opt in filteredOptions(col)"
                            :key="opt.key"
                            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded"
                            :class="
                              getCellValue(row, col) === opt.key && 'bg-primary/10 text-primary'
                            "
                            @click="selectCell(row, col, opt.key)"
                          >
                            {{ opt.value
                            }}<Check
                              v-if="getCellValue(row, col) === opt.key"
                              class="size-3 ml-auto opacity-60"
                            />
                          </button>
                        </div>
                        <div v-if="canManage" class="border-t border-border p-2">
                          <input
                            v-model="selectSearch"
                            placeholder="+ New option"
                            class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring"
                            @keydown.enter.prevent="addCellOption(col, row)"
                          />
                        </div>
                      </PopoverContent>
                    </Popover>
                  </div>
                  <div v-else class="px-2 py-1">
                    <span
                      :class="
                        !findOptionLabel(col.config?.options || [], getCellValue(row, col)) &&
                        'text-muted-foreground/40'
                      "
                      class="text-sm"
                      >{{
                        findOptionLabel(col.config?.options || [], getCellValue(row, col)) ||
                        "\u2014"
                      }}</span
                    >
                  </div>
                </template>

                <!-- ── Multi-select ── -->
                <template v-else-if="col.type === 'multi_select'">
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
                          class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-muted/50"
                        >
                          <div
                            v-if="
                              resolveMultiLabels(getCellValue(row, col), col.config?.options || [])
                                .length
                            "
                            class="flex flex-wrap gap-1"
                          >
                            <Badge
                              v-for="lbl in resolveMultiLabels(
                                getCellValue(row, col),
                                col.config?.options || [],
                              )"
                              :key="lbl"
                              class="text-[10px]"
                              >{{ lbl }}</Badge
                            >
                          </div>
                          <span v-else class="text-muted-foreground/40 truncate">Select...</span>
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
                            v-for="opt in filteredOptions(col)"
                            :key="opt.key"
                            class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded"
                            :class="
                              ((getCellValue(row, col) as string[]) || []).includes(opt.key) &&
                              'bg-primary/10'
                            "
                            @click="toggleMultiSelectCell(row, col, opt.key)"
                          >
                            <Checkbox
                              :checked="
                                ((getCellValue(row, col) as string[]) || []).includes(opt.key)
                              "
                              class="pointer-events-none"
                            />{{ opt.value }}
                          </button>
                        </div>
                        <div v-if="canManage" class="border-t border-border p-2">
                          <input
                            v-model="selectSearch"
                            placeholder="+ New option"
                            class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring"
                            @keydown.enter.prevent="addCellOption(col, row)"
                          />
                        </div>
                      </PopoverContent>
                    </Popover>
                  </div>
                  <div v-else class="px-2 py-1">
                    <div
                      v-if="
                        resolveMultiLabels(getCellValue(row, col), col.config?.options || []).length
                      "
                      class="flex flex-wrap gap-1"
                    >
                      <Badge
                        v-for="lbl in resolveMultiLabels(
                          getCellValue(row, col),
                          col.config?.options || [],
                        )"
                        :key="lbl"
                        class="text-[10px]"
                        >{{ lbl }}</Badge
                      >
                    </div>
                    <span v-else class="text-muted-foreground/40 text-sm">\u2014</span>
                  </div>
                </template>

                <!-- ── Formula (always read-only) ── -->
                <template v-else-if="col.type === 'formula'">
                  <button
                    v-if="canEdit"
                    type="button"
                    class="absolute inset-0 px-2 flex items-center gap-1.5 text-sm cursor-pointer text-left hover:bg-muted/50"
                    @click="
                      live.pushEvent('open_formula_sidebar', {
                        'row-id': row.id,
                        'column-slug': col.slug,
                        'block-id': blockId,
                      })
                    "
                  >
                    <Sigma class="size-3 opacity-30 shrink-0" />
                    <span
                      :class="
                        getFormulaDisplay(row, col) === '\u2014' &&
                        'text-muted-foreground/40 italic'
                      "
                      >{{ getFormulaDisplay(row, col) }}</span
                    >
                  </button>
                  <div v-else class="px-2 py-1">
                    <span class="text-sm flex items-center gap-1">
                      <Sigma class="size-3 opacity-30 shrink-0" />
                      <template v-if="getFormulaDisplay(row, col) !== '\u2014'">{{
                        getFormulaDisplay(row, col)
                      }}</template>
                      <span
                        v-else
                        :class="
                          getFormulaExpression(row, col)
                            ? 'font-mono text-info/70 text-xs'
                            : 'text-muted-foreground/40'
                        "
                        >{{ getFormulaExpression(row, col) || "\u2014" }}</span
                      >
                    </span>
                  </div>
                </template>

                <!-- ── Date ── -->
                <template v-else-if="col.type === 'date'">
                  <input
                    v-if="canEdit"
                    type="date"
                    :value="getCellValue(row, col) as string"
                    class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none"
                    @change="
                      live.pushEvent('update_table_cell', {
                        'row-id': row.id,
                        'column-slug': col.slug,
                        value: ($event.target as HTMLInputElement).value,
                        type: 'date',
                      })
                    "
                  />
                  <div v-else class="px-2 py-1">
                    <span
                      :class="!getCellValue(row, col) && 'text-muted-foreground/40'"
                      class="text-sm"
                      >{{ formatDate(getCellValue(row, col)) }}</span
                    >
                  </div>
                </template>

                <!-- ── Text / Number (click to edit) ── -->
                <template v-else>
                  <template v-if="canEdit">
                    <template v-if="isCellEditing(row, col)">
                      <input
                        ref="cellInput"
                        v-model="editingCellValue"
                        :type="col.type === 'number' ? 'number' : 'text'"
                        v-bind="inputAttrs(col)"
                        class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none"
                        @blur="saveCell(row, col)"
                        @keydown.enter.prevent="saveCell(row, col)"
                      />
                    </template>
                    <div
                      v-else
                      class="absolute inset-0 px-2 flex items-center text-sm cursor-text"
                      @click="startEditCell(row, col)"
                    >
                      {{ displayValue(getCellValue(row, col), "") }}
                    </div>
                  </template>
                  <div v-else class="px-2 py-1">
                    <span
                      :class="
                        !getCellValue(row, col) &&
                        getCellValue(row, col) !== 0 &&
                        'text-muted-foreground/40'
                      "
                      class="text-sm"
                    >
                      {{
                        displayValue(getCellValue(row, col), col.type === "number" ? "0" : "\u2014")
                      }}
                    </span>
                  </div>
                </template>
              </td>
            </TableDraggableRow>

            <!-- Empty state -->
            <tr v-if="localRows.length === 0">
              <td
                :colspan="columns.length + 1"
                class="text-center text-sm text-muted-foreground py-6"
              >
                No rows yet.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- ═══ ADD COLUMN BAR (canManage only) ═══ -->
      <button
        v-if="canManage"
        class="flex items-center justify-center w-6 shrink-0 rounded-lg border border-border/50 bg-muted/20 hover:bg-muted/50 text-muted-foreground/30 hover:text-muted-foreground/60 transition-all cursor-pointer opacity-0 group-hover/table:opacity-100"
        @click="addColumn"
      >
        <Plus class="size-3.5" />
      </button>
    </div>

    <!-- ═══ ADD ROW BAR (canManage only) ═══ -->
    <button
      v-if="canManage"
      class="flex items-center justify-center w-full h-6 mt-2 rounded-lg border border-border/50 bg-muted/20 hover:bg-muted/50 text-muted-foreground/30 hover:text-muted-foreground/60 transition-all cursor-pointer opacity-0 group-hover/table:opacity-100"
      @click="addRow"
    >
      <Plus class="size-3.5" />
    </button>
  </div>
</template>
