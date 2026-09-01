<script setup lang="ts">
/**
 * Props-driven facade over the app's Table compound (columns + rows data;
 * React children can't interleave with Vue table internals).
 * Cell values render as text.
 */
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableEmpty,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";

export interface TableColumn {
  key: string;
  label: string;
  class?: string;
}

const {
  columns = [],
  rows = [],
  caption,
  emptyText = "No results.",
} = defineProps<{
  columns?: TableColumn[];
  rows?: Record<string, unknown>[];
  caption?: string;
  emptyText?: string;
  class?: string;
}>();
</script>

<template>
  <Table :class="$props.class">
    <TableCaption v-if="caption">{{ caption }}</TableCaption>
    <TableHeader>
      <TableRow>
        <TableHead v-for="col in columns" :key="col.key" :class="col.class">
          {{ col.label }}
        </TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      <TableEmpty v-if="rows.length === 0" :colspan="columns.length">
        {{ emptyText }}
      </TableEmpty>
      <TableRow v-for="(row, ri) in rows" :key="ri">
        <TableCell v-for="col in columns" :key="col.key" :class="col.class">
          {{ row[col.key] }}
        </TableCell>
      </TableRow>
    </TableBody>
  </Table>
</template>
