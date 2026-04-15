<script setup lang="ts">
import { Plus } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import type {
  TableColumn,
  TableRow,
} from "../../../types";
import THead from "@modules/sheets/components/blocks/table/THead.vue";
import TBody from '@modules/sheets/components/blocks/table/TBody.vue'

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
// Add column / row (canManage only)
// ══════════════════════════════════════════════════════════════
function addColumn(): void {
  live.pushEvent("add_table_column", { "block-id": blockId });
}

function addRow(): void {
  live.pushEvent("add_table_row", { "block-id": blockId });
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
          <THead :columns="columns" :can-manage="canManage" />

          <TBody
            :block-id="blockId"
            :rows="rows"
            :columns="columns"
            :can-edit="canEdit"
            :can-manage="canManage"
          />
        </table>

        <button
          v-if="canManage"
          class="flex items-center justify-center w-full h-6 mt-2 rounded-lg border border-border/50 bg-card/80 hover:bg-card text-foreground/50 hover:text-foreground transition-all cursor-pointer opacity-0 group-hover/table:opacity-100"
          @click="addRow"
        >
          <Plus class="size-3.5" />
        </button>
      </div>

      <!-- ═══ ADD COLUMN BAR (canManage only) ═══ -->
      <button
        v-if="canManage"
        class="flex items-center justify-center w-6 mb-6 shrink-0 rounded-lg border border-border/50 bg-card/80 hover:bg-card text-foreground/50 hover:text-foreground transition-all cursor-pointer opacity-0 group-hover/table:opacity-100"
        @click="addColumn"
      >
        <Plus class="size-3.5" />
      </button>
    </div>

    <!-- ═══ ADD ROW BAR (canManage only) ═══ -->
  </div>
</template>
