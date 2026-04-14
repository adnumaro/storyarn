<script setup lang="ts">
import THeadMenu from "@modules/sheets/components/blocks/table/THeadMenu.vue";
import type { TableColumn } from "@modules/sheets/types.ts";
import { computed } from "vue";

const { columns, canManage = false } = defineProps<{
  columns: TableColumn[];
  canManage?: boolean;
}>();

const isLastColumn = computed(() => columns.length <= 1);
</script>

<template>
  <thead>
    <tr
      class="bg-card/60 border-b border-border [&>th:first-child]:rounded-tl-lg [&>th:last-child]:rounded-tr-lg"
    >
      <!-- Row label header (empty) -->
      <th class="font-medium sticky left-0 z-10 bg-card/60" />

      <!-- Column headers -->
      <th
        v-for="col in columns"
        :key="col.id"
        class="font-medium text-foreground/70 relative overflow-hidden"
      >
        <THeadMenu :column="col" :can-manage="canManage" :is-last-column="isLastColumn" />
      </th>
    </tr>
  </thead>
</template>
