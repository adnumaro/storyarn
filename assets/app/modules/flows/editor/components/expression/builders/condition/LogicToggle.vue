<script setup lang="ts">
/**
 * AND/OR logic toggle: "Match [all|any] of the {label}"
 */

const {
  logic = "all",
  kind = "rules",
  disabled = false,
} = defineProps<{
  logic?: "all" | "any";
  /** What the choice applies to; Spanish words agree with it. */
  kind?: "rules" | "blocks" | "group";
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:logic": [logic: "all" | "any"];
}>();

const LOGIC_KEYS = {
  rules: {
    all: "common.condition_builder.logic.rules.all",
    any: "common.condition_builder.logic.rules.any",
    suffixAll: "common.condition_builder.logic.rules.suffix_all",
    suffixAny: "common.condition_builder.logic.rules.suffix_any",
  },
  blocks: {
    all: "common.condition_builder.logic.blocks.all",
    any: "common.condition_builder.logic.blocks.any",
    suffixAll: "common.condition_builder.logic.blocks.suffix_all",
    suffixAny: "common.condition_builder.logic.blocks.suffix_any",
  },
  group: {
    all: "common.condition_builder.logic.group.all",
    any: "common.condition_builder.logic.group.any",
    suffixAll: "common.condition_builder.logic.group.suffix_all",
    suffixAny: "common.condition_builder.logic.group.suffix_any",
  },
} as const;
</script>

<template>
  <div class="flex items-center gap-1.5 text-xs">
    <span class="text-muted-foreground">{{ $t("common.condition_builder.logic.match") }}</span>
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
        {{ $t(LOGIC_KEYS[kind].all) }}
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
        {{ $t(LOGIC_KEYS[kind].any) }}
      </button>
    </div>
    <span class="text-muted-foreground">{{
      $t(logic === "all" ? LOGIC_KEYS[kind].suffixAll : LOGIC_KEYS[kind].suffixAny)
    }}</span>
  </div>
</template>
