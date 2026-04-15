<script setup lang="ts">
import TableRowActions from '@modules/sheets/components/blocks/table/TableRowActions.vue'
import TableDraggableRow from '@modules/sheets/components/blocks/table/TableDraggableRow.vue'
import { TableColumn, TableRow } from '../../../types'
import { ref, useTemplateRef, watch } from 'vue'
import { IDragEvent, makeDroppable } from '@vue-dnd-kit/core'
import { useLive } from '@composables/useLive.ts'
import TTextNumberCell from '@modules/sheets/components/blocks/table/tbodyCells/TTextNumberCell.vue'
import TDateCell from '@modules/sheets/components/blocks/table/tbodyCells/TDateCell.vue'
import TMultiSelectCell from '@modules/sheets/components/blocks/table/tbodyCells/TMultiSelectCell.vue'
import TSelectCell from '@modules/sheets/components/blocks/table/tbodyCells/TSelectCell.vue'
import TBooleanCell from '@modules/sheets/components/blocks/table/tbodyCells/TBooleanCell.vue'
import TFormulaCell from '@modules/sheets/components/blocks/table/tbodyCells/TFormulaCell.vue'

const {
  blockId,
  columns,
  rows,
  canEdit = false,
  canManage = false,
} = defineProps<{
  blockId: number | string;
  columns: TableColumn[];
  rows: TableRow[];
  canEdit?: boolean;
  // canManage: can modify structure (columns/rows). False for inherited (schema_locked) tables.
  canManage?: boolean;
}>()

const live = useLive()

// ══════════════════════════════════════════════════════════════
// Row reorder via vue-dnd-kit (canManage only)
// ══════════════════════════════════════════════════════════════
const rowGroup = `table-rows-${ blockId }`
const localRows = ref<TableRow[]>([...rows])
watch(
  () => rows,
  (v) => {
    localRows.value = [...v]
  },
)

const tbodyRef = useTemplateRef('tbodyRef')
makeDroppable(
  tbodyRef,
  {
    groups: [rowGroup],
    events: {
      onDrop: (e: IDragEvent) => {
        const result = e.helpers.suggestSort('vertical')
        if (!result) {
          return
        }
        localRows.value = result.sourceItems as TableRow[]
        const ids = localRows.value.map((r) => r.id)
        live.pushEvent('reorder_table_rows', {
          block_id: blockId,
          row_ids: ids,
        })
      },
    },
  },
  () => localRows.value,
)
</script>

<template>
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
    <td class="sticky left-0 z-10 bg-card/60 font-medium text-foreground text-sm">
      <TableRowActions :row="row" :rows="rows" :can-manage="canManage" />
    </td>

    <!-- ══ Data cells ══ -->
    <td v-for="column in columns" :key="column.id" class="p-0! relative h-1">
      <TBooleanCell
        v-if="column.type === 'boolean'"
        :row="row"
        :column="column"
        :can-edit="canEdit"
      />

      <TSelectCell
        v-else-if="column.type === 'select'"
        :row="row"
        :column="column"
        :can-edit="canEdit"
        :can-manage="canManage"
      />

      <TMultiSelectCell
        v-else-if="column.type === 'multi_select'"
        :row="row"
        :column="column"
        :can-edit="canEdit"
        :can-manage="canManage"
      />

      <TFormulaCell
        v-else-if="column.type === 'formula'"
        :block-id="blockId"
        :row="row"
        :column="column"
        :can-edit="canEdit"
      />

      <TDateCell
        v-else-if="column.type === 'date'"
        :row="row"
        :column="column"
        :can-edit="canEdit"
      />

      <TTextNumberCell
        v-else
        :row="row"
        :column="column"
        :can-edit="canEdit"
      />
    </td>
  </TableDraggableRow>

  <!-- Empty state -->
  <tr v-if="localRows.length === 0">
    <td :colspan="columns.length + 1" class="text-center text-sm text-foreground py-6">
      No rows yet.
    </td>
  </tr>
  </tbody>
</template>

<style scoped>

</style>