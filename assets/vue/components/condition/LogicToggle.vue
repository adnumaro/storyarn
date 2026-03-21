<script setup>
/**
 * AND/OR logic toggle: "Match [all|any] of the {label}"
 */

defineProps({
  logic: { type: String, default: "all" },
  ofLabel: { type: String, default: "of the rules" },
  disabled: { type: Boolean, default: false },
})

const emit = defineEmits(["update:logic"])
</script>

<template>
  <div class="flex items-center gap-1.5 text-xs">
    <span class="text-muted-foreground">Match</span>
    <div class="inline-flex rounded-md border border-border overflow-hidden">
      <button
        type="button"
        :class="[
          'px-2 py-0.5 text-xs font-medium transition-colors',
          logic === 'all'
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:bg-accent/50',
        ]"
        :disabled="disabled"
        @click="emit('update:logic', 'all')"
      >
        all
      </button>
      <button
        type="button"
        :class="[
          'px-2 py-0.5 text-xs font-medium border-l border-border transition-colors',
          logic === 'any'
            ? 'bg-accent text-accent-foreground'
            : 'text-muted-foreground hover:bg-accent/50',
        ]"
        :disabled="disabled"
        @click="emit('update:logic', 'any')"
      >
        any
      </button>
    </div>
    <span class="text-muted-foreground">{{ ofLabel }}</span>
  </div>
</template>
