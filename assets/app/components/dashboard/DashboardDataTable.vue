<script setup lang="ts" generic="TRow extends DashboardTableRow">
import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-vue-next";
import type { Component } from "vue";
import DashboardPagination from "./DashboardPagination.vue";
import type { DashboardTableColumn, DashboardTablePagination, DashboardTableRow } from "./types";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";

const {
  title,
  rows,
  columns,
  pagination,
  totalLabel,
  previousLabel,
  nextLabel,
  hasActions = false,
} = defineProps<{
  title: string;
  rows: TRow[];
  columns: DashboardTableColumn[];
  pagination: DashboardTablePagination;
  totalLabel: string;
  previousLabel: string;
  nextLabel: string;
  hasActions?: boolean;
}>();

const emit = defineEmits<{
  sort: [column: string];
  page: [page: number];
}>();

defineSlots<{
  row(props: { row: TRow }): unknown;
  actions?(props: { row: TRow }): unknown;
}>();

function sortIcon(column: string): Component {
  if (pagination.sortBy !== column) return ArrowUpDown;
  return pagination.sortDir === "asc" ? ArrowUp : ArrowDown;
}

function ariaSort(column: string): "ascending" | "descending" | undefined {
  if (pagination.sortBy !== column) return undefined;
  return pagination.sortDir === "asc" ? "ascending" : "descending";
}
</script>

<template>
  <section data-testid="dashboard-data-table" class="space-y-2">
    <h2 class="text-sm font-medium">{{ title }}</h2>

    <div class="max-h-[60vh] overflow-auto rounded-lg border border-border bg-surface">
      <Table>
        <TableHeader>
          <TableRow class="sticky top-0 z-10 bg-muted/40 hover:bg-muted/40">
            <TableHead
              v-for="column in columns"
              :key="column.key"
              :class="[
                'text-xs font-medium uppercase text-muted-foreground',
                column.align === 'right' ? 'text-right' : 'text-left',
                column.hiddenClass,
              ]"
              :aria-sort="ariaSort(column.key)"
            >
              <button
                type="button"
                class="inline-flex items-center gap-1 transition-colors hover:text-foreground"
                :class="column.align === 'right' && 'ml-auto'"
                @click="emit('sort', column.key)"
              >
                {{ column.label }}
                <component :is="sortIcon(column.key)" class="size-3" aria-hidden="true" />
              </button>
            </TableHead>
            <TableHead
              v-if="hasActions"
              data-testid="dashboard-data-table-actions-header"
              class="w-10"
            />
          </TableRow>
        </TableHeader>

        <TableBody>
          <TableRow v-for="row in rows" :key="row.id">
            <slot name="row" :row="row" />
            <TableCell
              v-if="hasActions"
              data-testid="dashboard-data-table-actions-cell"
              class="w-10 text-right"
            >
              <slot name="actions" :row="row" />
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <DashboardPagination
      v-if="pagination.total > 0"
      :pagination="pagination"
      :total-label="totalLabel"
      :previous-label="previousLabel"
      :next-label="nextLabel"
      @page="emit('page', $event)"
    />
  </section>
</template>
