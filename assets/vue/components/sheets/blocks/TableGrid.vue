<script setup>
import { ref, watch, nextTick, useTemplateRef } from "vue"
import { useLive } from "@/vue/composables/useLive"
import { makeDroppable } from "@vue-dnd-kit/core"
import {
  Plus, Trash2, ChevronDown, ChevronRight, GripVertical, X, Check,
  Hash, Type, ToggleLeft, CircleDot, List, Calendar, Sigma, Link, Columns2,
  Lock, Asterisk, ArrowLeftRight, Settings, SlidersHorizontal, Layers,
  ArrowLeft,
} from "lucide-vue-next"
import { Checkbox } from "@/vue/components/ui/checkbox"
import { Badge } from "@/vue/components/ui/badge"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/vue/components/ui/popover"
import { Separator } from "@/vue/components/ui/separator"
import TableDraggableRow from "./TableDraggableRow.vue"

const props = defineProps({
  blockId: { type: [Number, String], required: true },
  columns: { type: Array, default: () => [] },
  rows: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  // canManage: can modify structure (columns/rows). False for inherited (schema_locked) tables.
  canManage: { type: Boolean, default: false },
})

const live = useLive()

// ── Type icons & labels ──
const typeIcons = {
  number: Hash, text: Type, boolean: ToggleLeft, select: CircleDot,
  multi_select: List, date: Calendar, formula: Sigma, reference: Link,
}
const typeLabels = {
  number: "Number", text: "Text", boolean: "Boolean", select: "Select",
  multi_select: "Multi Select", date: "Date", reference: "Reference", formula: "Formula",
}
const allTypes = ["number", "text", "boolean", "select", "multi_select", "date", "reference", "formula"]

function typeIcon(type) { return typeIcons[type] || Columns2 }

// ══════════════════════════════════════════════════════════════
// Column dropdown (canManage only)
// ══════════════════════════════════════════════════════════════
const openColDropdownId = ref(null)
const colDropdownPanel = ref("main")
const colRenameValue = ref("")
const colNewOptionValue = ref("")
const colOptionEdits = ref({})

function openColDropdown(col) {
  openColDropdownId.value = col.id
  colDropdownPanel.value = "main"
  colRenameValue.value = col.name
  colNewOptionValue.value = ""
  colOptionEdits.value = {}
}

function closeColDropdown() {
  const col = props.columns.find(c => c.id === openColDropdownId.value)
  if (col && colRenameValue.value.trim() && colRenameValue.value.trim() !== col.name) {
    live.pushEvent("rename_table_column", { "column-id": col.id, value: colRenameValue.value.trim() })
  }
  openColDropdownId.value = null
}

function saveColRename(col) {
  const name = colRenameValue.value.trim()
  if (name && name !== col.name) {
    live.pushEvent("rename_table_column", { "column-id": col.id, value: name })
  }
}

function toggleColConstant(col) {
  live.pushEvent("toggle_table_column_constant", { "column-id": col.id })
}

function toggleColRequired(col) {
  live.pushEvent("toggle_table_column_required", { "column-id": col.id })
}

function changeColType(col, newType) {
  if (col.type !== newType) {
    live.pushEvent("change_table_column_type", { "column-id": col.id, "new-type": newType })
  }
}

function deleteColumn(col) {
  live.pushEvent("delete_table_column", { "column-id": col.id })
  openColDropdownId.value = null
}

function addColumnOption(col) {
  const label = colNewOptionValue.value.trim()
  if (!label) return
  live.pushEvent("add_table_column_option", { "column-id": col.id, value: label })
  colNewOptionValue.value = ""
}

function updateColumnOption(col, index) {
  const val = colOptionEdits.value[index]
  if (val != null && val.trim()) {
    live.pushEvent("update_table_column_option", { "column-id": col.id, index, value: val.trim() })
  }
}

function removeColumnOption(col, key) {
  live.pushEvent("remove_table_column_option", { "column-id": col.id, key })
}

function updateNumberConstraint(col, field, event) {
  live.pushEvent("update_number_constraint", { "column-id": col.id, field, value: event.target.value })
}

function toggleReferenceMultiple(col) {
  live.pushEvent("toggle_reference_multiple", { "column-id": col.id })
}

// ══════════════════════════════════════════════════════════════
// Row rename (canManage only)
// ══════════════════════════════════════════════════════════════
function saveRowName(row, event) {
  const name = event.target.value.trim()
  if (name && name !== row.name) {
    live.pushEvent("rename_table_row", { "row-id": row.id, value: name })
  }
}

function deleteRow(row) {
  live.pushEvent("delete_table_row", { "row-id": row.id })
}

// ══════════════════════════════════════════════════════════════
// Row reorder via vue-dnd-kit (canManage only)
// ══════════════════════════════════════════════════════════════
const rowGroup = `table-rows-${props.blockId}`
const localRows = ref([...props.rows])
watch(() => props.rows, (v) => { localRows.value = [...v] })

const tbodyRef = useTemplateRef("tbodyRef")
makeDroppable(tbodyRef, {
  groups: [rowGroup],
  events: {
    onDrop: (e) => {
      const result = e.helpers.suggestSort("vertical")
      if (!result) return
      localRows.value = result.sourceItems
      const ids = localRows.value.map(r => r.id)
      live.pushEvent("reorder_table_rows", { block_id: props.blockId, row_ids: ids })
    },
  },
}, () => localRows.value)

// ══════════════════════════════════════════════════════════════
// Cell editing — text/number (canEdit)
// ══════════════════════════════════════════════════════════════
const editingCell = ref(null)
const editingCellValue = ref("")
const cellInput = ref(null)

function startEditCell(row, col) {
  if (!props.canEdit) return
  editingCell.value = { rowId: row.id, colSlug: col.slug }
  editingCellValue.value = row.cells?.[col.slug] ?? ""
  nextTick(() => cellInput.value?.focus())
}

function saveCell(row, col) {
  editingCell.value = null
  live.pushEvent("update_table_cell", {
    "row-id": row.id, "column-slug": col.slug,
    value: editingCellValue.value, type: col.type,
  })
}

function isCellEditing(row, col) {
  return editingCell.value?.rowId === row.id && editingCell.value?.colSlug === col.slug
}

// ══════════════════════════════════════════════════════════════
// Boolean toggle (canEdit)
// ══════════════════════════════════════════════════════════════
function toggleBoolean(row, col) {
  live.pushEvent("toggle_table_cell_boolean", { "row-id": row.id, "column-slug": col.slug })
}

// ══════════════════════════════════════════════════════════════
// Select / Multi-select cells (canEdit)
// ══════════════════════════════════════════════════════════════
const selectSearch = ref("")

function selectCell(row, col, key) {
  live.pushEvent("select_table_cell", { "row-id": row.id, "column-slug": col.slug, key })
}

function toggleMultiSelectCell(row, col, key) {
  live.pushEvent("toggle_table_cell_multi_select", { "row-id": row.id, "column-slug": col.slug, key })
}

function addCellOption(col, row) {
  const label = selectSearch.value.trim()
  if (!label) return
  live.pushEvent("add_table_cell_option", {
    "column-id": col.id, "row-id": row.id, "column-slug": col.slug, value: label,
  })
  selectSearch.value = ""
}

function filteredOptions(col) {
  const options = col.config?.options || []
  const q = selectSearch.value.toLowerCase()
  if (!q) return options
  return options.filter(o => (o.value || "").toLowerCase().includes(q))
}

// ══════════════════════════════════════════════════════════════
// Add column / row (canManage only)
// ══════════════════════════════════════════════════════════════
function addColumn() {
  live.pushEvent("add_table_column", { "block-id": props.blockId })
}

function addRow() {
  live.pushEvent("add_table_row", { "block-id": props.blockId })
}

// ══════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════
function getCellValue(row, col) {
  return row.cells?.[col.slug] ?? ""
}

function getFormulaDisplay(row, col) {
  const cell = row.cells?.[col.slug]
  if (cell == null) return "—"
  if (typeof cell === "object") {
    // __result is injected by compute_formulas on the server
    if ("__result" in cell) {
      return cell.__result != null ? cell.__result : "—"
    }
    // Has expression but no computed result yet
    return "—"
  }
  return cell !== "" ? cell : "—"
}

function getFormulaExpression(row, col) {
  const cell = row.cells?.[col.slug]
  if (typeof cell === "object" && cell.expression) return cell.expression
  return ""
}

function findOptionLabel(options, key) {
  if (!key) return null
  const opt = options.find(o => o.key === key)
  return opt?.value || null
}

function resolveMultiLabels(value, options) {
  if (!Array.isArray(value) || value.length === 0) return []
  const map = Object.fromEntries(options.map(o => [o.key, o.value]))
  return value.map(k => map[k] || k)
}

function formatDate(val) {
  if (!val) return "—"
  try {
    const d = new Date(val + "T00:00:00")
    return d.toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
  } catch { return val }
}

function displayValue(val, fallback) {
  if (val == null || val === "") return fallback
  return String(val)
}

function inputAttrs(col) {
  if (col.type !== "number") return {}
  const c = col.config || {}
  const attrs = {}
  if (c.min != null) attrs.min = c.min
  if (c.max != null) attrs.max = c.max
  attrs.step = c.step || "any"
  return attrs
}
</script>

<template>
  <div class="group/table w-full max-w-full" @click.stop>
    <div class="flex w-full max-w-full min-w-0 items-stretch gap-2">
      <!-- ═══ TABLE ═══ -->
      <div class="flex-1 min-w-0 max-w-full overflow-auto rounded-lg border border-border">
        <table class="min-w-full w-max text-sm [&_:is(th,td)]:border-r [&_:is(th,td)]:border-border [&_:is(th,td):last-child]:border-r-0" style="table-layout: fixed">
          <colgroup>
            <col style="width: 8rem" />
            <col v-for="col in columns" :key="col.id" :style="{ width: (col.config?.width || 150) + 'px' }" />
          </colgroup>

          <!-- ═══ HEADER ═══ -->
          <thead>
            <tr class="bg-muted/50 border-b border-border [&>th:first-child]:rounded-tl-lg [&>th:last-child]:rounded-tr-lg">
              <!-- Row label header (empty) -->
              <th class="font-medium text-muted-foreground/60 sticky left-0 z-10 bg-muted/50" />

              <!-- Column headers -->
              <th v-for="col in columns" :key="col.id" class="font-medium text-muted-foreground/70 relative overflow-hidden">
                <!-- ══ Editable: dropdown with management options (canManage) ══ -->
                <Popover v-if="canManage" :open="openColDropdownId === col.id" @update:open="(v) => v ? openColDropdown(col) : closeColDropdown()">
                  <PopoverTrigger as-child>
                    <button type="button" class="flex flex-col items-start cursor-pointer hover:text-foreground w-full min-w-0 px-3 py-2">
                      <span class="flex items-center gap-1.5 max-w-full">
                        <component :is="typeIcon(col.type)" class="size-3.5 opacity-50 shrink-0" />
                        <span class="truncate">{{ col.name }}</span>
                        <span v-if="col.required" class="text-destructive text-xs shrink-0">*</span>
                        <ChevronDown class="size-3 opacity-40 shrink-0" />
                      </span>
                      <span class="text-[10px] font-normal text-muted-foreground/30 truncate max-w-full">{{ col.slug }}</span>
                    </button>
                  </PopoverTrigger>
                  <PopoverContent align="start" :side-offset="4" class="w-56 p-0 z-[1030]">
                    <!-- Main panel -->
                    <div v-if="colDropdownPanel === 'main'" class="p-1">
                      <div class="flex items-center gap-1.5 px-2 py-1.5 mb-1">
                        <component :is="typeIcon(col.type)" class="size-3.5 opacity-50 shrink-0" />
                        <input v-model="colRenameValue" class="bg-transparent outline-none border-none text-sm font-medium w-full px-0" @blur="saveColRename(col)" @keydown.enter.prevent="saveColRename(col)" />
                      </div>
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="toggleColConstant(col)">
                        <Lock class="size-3.5 opacity-60" /><span class="flex-1 text-left">Constant</span><Check v-if="col.is_constant" class="size-3.5 opacity-60" />
                      </button>
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="toggleColRequired(col)">
                        <Asterisk class="size-3.5 opacity-60" /><span class="flex-1 text-left">Required</span><Check v-if="col.required" class="size-3.5 opacity-60" />
                      </button>
                      <Separator class="my-1" />
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="colDropdownPanel = 'type'">
                        <ArrowLeftRight class="size-3.5 opacity-60" /><span class="flex-1 text-left">Change type</span><ChevronRight class="size-3.5 opacity-40" />
                      </button>
                      <button v-if="col.type === 'select' || col.type === 'multi_select'" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="colDropdownPanel = 'options'">
                        <Settings class="size-3.5 opacity-60" /><span class="flex-1 text-left">Options</span><ChevronRight class="size-3.5 opacity-40" />
                      </button>
                      <button v-if="col.type === 'number'" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="colDropdownPanel = 'number'">
                        <SlidersHorizontal class="size-3.5 opacity-60" /><span class="flex-1 text-left">Constraints</span><ChevronRight class="size-3.5 opacity-40" />
                      </button>
                      <button v-if="col.type === 'reference'" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="colDropdownPanel = 'reference'">
                        <Settings class="size-3.5 opacity-60" /><span class="flex-1 text-left">Settings</span><ChevronRight class="size-3.5 opacity-40" />
                      </button>
                      <Separator class="my-1" />
                      <button :disabled="columns.length <= 1" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent text-destructive disabled:opacity-30 disabled:pointer-events-none" @click="deleteColumn(col)">
                        <Trash2 class="size-3.5" /><span>Delete column</span>
                      </button>
                    </div>
                    <!-- Type panel -->
                    <div v-else-if="colDropdownPanel === 'type'" class="p-1">
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1" @click="colDropdownPanel = 'main'"><ArrowLeft class="size-3.5" /><span>Change type</span></button>
                      <Separator class="mb-1" />
                      <button v-for="t in allTypes" :key="t" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" :class="col.type === t && 'bg-accent'" @click="changeColType(col, t)">
                        <component :is="typeIcon(t)" class="size-3.5 opacity-60" /><span class="flex-1 text-left">{{ typeLabels[t] }}</span><Check v-if="col.type === t" class="size-3.5 opacity-60" />
                      </button>
                    </div>
                    <!-- Options panel -->
                    <div v-else-if="colDropdownPanel === 'options'" class="p-1">
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1" @click="colDropdownPanel = 'main'"><ArrowLeft class="size-3.5" /><span>Options</span></button>
                      <Separator class="mb-1" />
                      <div v-for="(opt, idx) in (col.config?.options || [])" :key="opt.key" class="flex items-center gap-1 mb-1 px-1">
                        <input :value="colOptionEdits[idx] ?? opt.value" class="bg-transparent border border-border rounded px-2 py-1 text-xs flex-1 outline-none focus:border-ring" @input="colOptionEdits[idx] = $event.target.value" @blur="updateColumnOption(col, idx)" />
                        <button class="size-5 rounded flex items-center justify-center hover:bg-accent shrink-0" @click="removeColumnOption(col, opt.key)"><X class="size-3 text-muted-foreground" /></button>
                      </div>
                      <div class="px-1"><input v-model="colNewOptionValue" placeholder="+ Add option" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring" @keydown.enter.prevent="addColumnOption(col)" /></div>
                    </div>
                    <!-- Number constraints panel -->
                    <div v-else-if="colDropdownPanel === 'number'" class="p-1">
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1" @click="colDropdownPanel = 'main'"><ArrowLeft class="size-3.5" /><span>Constraints</span></button>
                      <Separator class="mb-2" />
                      <div class="space-y-2 px-2 pb-2">
                        <div><label class="text-xs font-medium opacity-70">Min value</label><input type="number" :value="col.config?.min" placeholder="No limit" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring" @blur="updateNumberConstraint(col, 'min', $event)" /></div>
                        <div><label class="text-xs font-medium opacity-70">Max value</label><input type="number" :value="col.config?.max" placeholder="No limit" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring" @blur="updateNumberConstraint(col, 'max', $event)" /></div>
                        <div><label class="text-xs font-medium opacity-70">Step</label><input type="number" :value="col.config?.step" placeholder="1" min="0.001" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring" @blur="updateNumberConstraint(col, 'step', $event)" /></div>
                      </div>
                    </div>
                    <!-- Reference settings panel -->
                    <div v-else-if="colDropdownPanel === 'reference'" class="p-1">
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1" @click="colDropdownPanel = 'main'"><ArrowLeft class="size-3.5" /><span>Settings</span></button>
                      <Separator class="mb-1" />
                      <button class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent" @click="toggleReferenceMultiple(col)">
                        <Layers class="size-3.5 opacity-60" /><span class="flex-1 text-left">Allow multiple</span><Check v-if="col.config?.multiple" class="size-3.5 opacity-60" />
                      </button>
                    </div>
                  </PopoverContent>
                </Popover>

                <!-- Read-only header (inherited or viewer) -->
                <div v-else class="px-3 py-2 min-w-0">
                  <span class="flex items-center gap-1.5 max-w-full">
                    <component :is="typeIcon(col.type)" class="size-3.5 opacity-50 shrink-0" />
                    <span class="truncate">{{ col.name }}</span>
                    <span v-if="col.required" class="text-destructive text-xs shrink-0">*</span>
                  </span>
                  <span class="text-[10px] font-normal text-muted-foreground/30 truncate block max-w-full">{{ col.slug }}</span>
                </div>
              </th>
            </tr>
          </thead>

          <!-- ═══ BODY ═══ -->
          <tbody ref="tbodyRef">
            <TableDraggableRow
              v-for="(row, rowIdx) in localRows" :key="row.id"
              :index="rowIdx"
              :items="localRows"
              :group="rowGroup"
              v-slot="{ isDragOver }"
            >
              <!-- ══ Row label cell ══ -->
              <td class="relative sticky left-0 z-10 bg-card font-medium text-muted-foreground/60 text-sm">
                <!-- Row handle + menu (canManage only) -->
                <div
                  v-if="canManage"
                  class="absolute -left-[5px] top-1/2 -translate-y-1/2 z-20 opacity-0 group-hover/row:opacity-100 transition-opacity"
                >
                  <Popover>
                    <PopoverTrigger as-child>
                      <button type="button" class="cursor-grab row-drag-handle p-0.5 rounded hover:bg-accent">
                        <GripVertical class="size-3.5 text-muted-foreground/40" />
                      </button>
                    </PopoverTrigger>
                    <PopoverContent align="start" :side-offset="4" class="w-36 p-1 z-[1030]">
                      <button
                        :disabled="rows.length <= 1"
                        class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent text-destructive disabled:opacity-30 disabled:pointer-events-none"
                        @click="deleteRow(row)"
                      >
                        <Trash2 class="size-3.5" />
                        <span>Delete</span>
                      </button>
                    </PopoverContent>
                  </Popover>
                </div>

                <!-- Row name: editable input (canManage) -->
                <label v-if="canManage" class="block cursor-text px-3 py-2">
                  <input
                    type="text"
                    :value="row.name"
                    class="w-full px-0 py-0.5 text-sm font-medium bg-transparent border-0 outline-none"
                    @blur="saveRowName(row, $event)"
                    @keydown.enter="saveRowName(row, $event)"
                  />
                  <span class="text-[10px] text-muted-foreground/30 block">{{ row.slug }}</span>
                </label>

                <!-- Row name: read-only (inherited / viewer) -->
                <div v-else class="px-3 py-2">
                  <span>{{ row.name }}</span>
                  <div class="text-[10px] text-muted-foreground/30">{{ row.slug }}</div>
                </div>
              </td>

              <!-- ══ Data cells ══ -->
              <td v-for="col in columns" :key="col.id" class="!p-0 relative h-1">

                <!-- ── Boolean ── -->
                <template v-if="col.type === 'boolean'">
                  <label v-if="canEdit" class="absolute inset-0 flex items-center justify-center cursor-pointer">
                    <Checkbox :checked="getCellValue(row, col) === true" @update:checked="toggleBoolean(row, col)" />
                  </label>
                  <div v-else class="px-2 py-1">
                    <Badge v-if="getCellValue(row, col) === true" class="text-[10px] bg-green-500/20 text-green-700 border-0">Yes</Badge>
                    <Badge v-else-if="getCellValue(row, col) === false" class="text-[10px] bg-red-500/20 text-red-700 border-0">No</Badge>
                    <span v-else class="text-muted-foreground/40 text-sm">—</span>
                  </div>
                </template>

                <!-- ── Select ── -->
                <template v-else-if="col.type === 'select'">
                  <div v-if="canEdit" class="absolute inset-0">
                    <Popover @update:open="(v) => { if (v) selectSearch = '' }">
                      <PopoverTrigger as-child>
                        <button class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-muted/50">
                          <span v-if="findOptionLabel(col.config?.options || [], getCellValue(row, col))" class="truncate">{{ findOptionLabel(col.config?.options || [], getCellValue(row, col)) }}</span>
                          <span v-else class="text-muted-foreground/40 truncate">Select...</span>
                        </button>
                      </PopoverTrigger>
                      <PopoverContent align="start" class="w-52 p-0 z-[1030]">
                        <div class="p-2"><input v-model="selectSearch" placeholder="Search..." class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring" /></div>
                        <div class="max-h-48 overflow-y-auto px-1 pb-1">
                          <button v-if="getCellValue(row, col)" class="flex items-center gap-2 w-full px-2 py-1.5 text-xs text-muted-foreground hover:bg-accent rounded" @click="selectCell(row, col, '')">
                            <X class="size-3" /> Clear
                          </button>
                          <button v-for="opt in filteredOptions(col)" :key="opt.key" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded" :class="getCellValue(row, col) === opt.key && 'bg-primary/10 text-primary'" @click="selectCell(row, col, opt.key)">
                            {{ opt.value }}<Check v-if="getCellValue(row, col) === opt.key" class="size-3 ml-auto opacity-60" />
                          </button>
                        </div>
                        <div v-if="canManage" class="border-t border-border p-2"><input v-model="selectSearch" placeholder="+ New option" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring" @keydown.enter.prevent="addCellOption(col, row)" /></div>
                      </PopoverContent>
                    </Popover>
                  </div>
                  <div v-else class="px-2 py-1">
                    <span :class="!findOptionLabel(col.config?.options || [], getCellValue(row, col)) && 'text-muted-foreground/40'" class="text-sm">{{ findOptionLabel(col.config?.options || [], getCellValue(row, col)) || "—" }}</span>
                  </div>
                </template>

                <!-- ── Multi-select ── -->
                <template v-else-if="col.type === 'multi_select'">
                  <div v-if="canEdit" class="absolute inset-0">
                    <Popover @update:open="(v) => { if (v) selectSearch = '' }">
                      <PopoverTrigger as-child>
                        <button class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-muted/50">
                          <div v-if="resolveMultiLabels(getCellValue(row, col), col.config?.options || []).length" class="flex flex-wrap gap-1">
                            <Badge v-for="lbl in resolveMultiLabels(getCellValue(row, col), col.config?.options || [])" :key="lbl" class="text-[10px]">{{ lbl }}</Badge>
                          </div>
                          <span v-else class="text-muted-foreground/40 truncate">Select...</span>
                        </button>
                      </PopoverTrigger>
                      <PopoverContent align="start" class="w-52 p-0 z-[1030]">
                        <div class="p-2"><input v-model="selectSearch" placeholder="Search..." class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring" /></div>
                        <div class="max-h-48 overflow-y-auto px-1 pb-1">
                          <button v-for="opt in filteredOptions(col)" :key="opt.key" class="flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-accent rounded" :class="(getCellValue(row, col) || []).includes(opt.key) && 'bg-primary/10'" @click="toggleMultiSelectCell(row, col, opt.key)">
                            <Checkbox :checked="(getCellValue(row, col) || []).includes(opt.key)" class="pointer-events-none" />{{ opt.value }}
                          </button>
                        </div>
                        <div v-if="canManage" class="border-t border-border p-2"><input v-model="selectSearch" placeholder="+ New option" class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring" @keydown.enter.prevent="addCellOption(col, row)" /></div>
                      </PopoverContent>
                    </Popover>
                  </div>
                  <div v-else class="px-2 py-1">
                    <div v-if="resolveMultiLabels(getCellValue(row, col), col.config?.options || []).length" class="flex flex-wrap gap-1">
                      <Badge v-for="lbl in resolveMultiLabels(getCellValue(row, col), col.config?.options || [])" :key="lbl" class="text-[10px]">{{ lbl }}</Badge>
                    </div>
                    <span v-else class="text-muted-foreground/40 text-sm">—</span>
                  </div>
                </template>

                <!-- ── Formula (always read-only) ── -->
                <template v-else-if="col.type === 'formula'">
                  <button
                    v-if="canEdit"
                    type="button"
                    class="absolute inset-0 px-2 flex items-center gap-1.5 text-sm cursor-pointer text-left hover:bg-muted/50"
                    @click="live.pushEvent('open_formula_sidebar', { 'row-id': row.id, 'column-slug': col.slug, 'block-id': blockId })"
                  >
                    <Sigma class="size-3 opacity-30 shrink-0" />
                    <span :class="getFormulaDisplay(row, col) === '—' && 'text-muted-foreground/40 italic'">{{ getFormulaDisplay(row, col) }}</span>
                  </button>
                  <div v-else class="px-2 py-1">
                    <span class="text-sm flex items-center gap-1">
                      <Sigma class="size-3 opacity-30 shrink-0" />
                      <template v-if="getFormulaDisplay(row, col) !== '—'">{{ getFormulaDisplay(row, col) }}</template>
                      <span v-else :class="getFormulaExpression(row, col) ? 'font-mono text-info/70 text-xs' : 'text-muted-foreground/40'">{{ getFormulaExpression(row, col) || "—" }}</span>
                    </span>
                  </div>
                </template>

                <!-- ── Date ── -->
                <template v-else-if="col.type === 'date'">
                  <input
                    v-if="canEdit"
                    type="date"
                    :value="getCellValue(row, col)"
                    class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none"
                    @change="live.pushEvent('update_table_cell', { 'row-id': row.id, 'column-slug': col.slug, value: $event.target.value, type: 'date' })"
                  />
                  <div v-else class="px-2 py-1">
                    <span :class="!getCellValue(row, col) && 'text-muted-foreground/40'" class="text-sm">{{ formatDate(getCellValue(row, col)) }}</span>
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
                    <div v-else class="absolute inset-0 px-2 flex items-center text-sm cursor-text" @click="startEditCell(row, col)">
                      {{ displayValue(getCellValue(row, col), "") }}
                    </div>
                  </template>
                  <div v-else class="px-2 py-1">
                    <span :class="!getCellValue(row, col) && getCellValue(row, col) !== 0 && 'text-muted-foreground/40'" class="text-sm">
                      {{ displayValue(getCellValue(row, col), col.type === "number" ? "0" : "—") }}
                    </span>
                  </div>
                </template>
              </td>
            </TableDraggableRow>

            <!-- Empty state -->
            <tr v-if="localRows.length === 0">
              <td :colspan="columns.length + 1" class="text-center text-sm text-muted-foreground py-6">
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
