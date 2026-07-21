<script setup lang="ts">
import { watch } from "vue";
import { useCommand } from "@components/ui/command";

const emit = defineEmits<{
  noResults: [queryLength: number];
}>();

const { filterState } = useCommand();

// Emits once per entry into the "no results" state (not per keystroke while
// already empty) — the analytics payload carries the query LENGTH only.
watch(
  () => !!filterState.search && filterState.filtered.count === 0,
  (isEmpty) => {
    if (isEmpty) emit("noResults", filterState.search.length);
  },
);
</script>

<template>
  <div
    v-if="!!filterState.search && filterState.filtered.count === 0"
    data-slot="command-empty"
    class="py-6 text-center text-sm text-muted-foreground"
  >
    <slot />
  </div>
</template>
