<script setup lang="ts">
import { computed } from "vue";
import { STATUS_I18N, TONES, isTranslationStatus, statusTone } from "../../domain/status";

/**
 * One translation status, always the same dot, colour and label. `inline`
 * is the row form (dot + text), `pill` the editor header form.
 */
const { status, variant = "inline" } = defineProps<{
  status: string;
  variant?: "inline" | "pill";
}>();

const tone = computed(() => TONES[statusTone(status)]);
const labelKey = computed(() =>
  isTranslationStatus(status) ? STATUS_I18N[status] : STATUS_I18N.pending,
);
</script>

<template>
  <span
    v-if="variant === 'pill'"
    :class="[
      'inline-flex items-center gap-1.5 rounded-full py-0.5 pr-2.5 pl-2 text-xs font-medium',
      tone.pill,
    ]"
  >
    <span :class="['size-[7px] shrink-0 rounded-full', tone.dot]" aria-hidden="true" />
    {{ $t(labelKey) }}
  </span>
  <span v-else :class="['inline-flex items-center gap-1.5 font-medium', tone.text]">
    <span :class="['size-[7px] shrink-0 rounded-full', tone.dot]" aria-hidden="true" />
    {{ $t(labelKey) }}
  </span>
</template>
