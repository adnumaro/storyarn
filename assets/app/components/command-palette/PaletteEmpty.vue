<script setup lang="ts">
import { watch } from "vue";
import { useCommand } from "@components/ui/command";

const { enabled = true } = defineProps<{
  enabled?: boolean;
}>();

const emit = defineEmits<{
  noResults: [queryLength: number];
}>();

const { filterState } = useCommand();

// Emits once per entry into the "no results" state (not per keystroke while
// already empty) — the analytics payload carries the query LENGTH only.
watch(
  () => enabled && !!filterState.search.trim() && filterState.filtered.count === 0,
  (isEmpty) => {
    if (isEmpty) emit("noResults", filterState.search.trim().length);
  },
);
</script>

<template>
  <div
    v-if="enabled && !!filterState.search.trim() && filterState.filtered.count === 0"
    data-slot="command-empty"
    class="py-6 text-center text-sm text-muted-foreground"
  >
    <slot />
  </div>
</template>
