<script setup lang="ts">
import { Sparkles, TriangleAlert } from "@lucide/vue";
import { computed } from "vue";
import { TONES } from "../../domain/status";

/**
 * The two derived flags of a string: Outdated (the source changed after the
 * translation was written) and Machine (last written by DeepL).
 */
const { kind, variant = "inline" } = defineProps<{
  kind: "outdated" | "machine";
  variant?: "inline" | "pill";
}>();

const tone = computed(() => TONES[kind]);
const icon = computed(() => (kind === "outdated" ? TriangleAlert : Sparkles));
const labelKey = computed(() =>
  kind === "outdated" ? "localization.flags.outdated" : "localization.flags.machine_short",
);
</script>

<template>
  <span
    v-if="variant === 'pill'"
    :class="[
      'inline-flex items-center gap-1 rounded-full py-0.5 pr-2.5 pl-2 text-xs font-medium',
      tone.pill,
    ]"
  >
    <component :is="icon" class="size-3" aria-hidden="true" />
    {{ $t(labelKey) }}
  </span>
  <span v-else :class="['inline-flex items-center gap-1', tone.text]">
    <component :is="icon" class="size-[11px]" aria-hidden="true" />
    {{ $t(labelKey) }}
  </span>
</template>
