<script setup lang="ts">
import { computed } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { TONES, type Tone } from "../../domain/status";

/**
 * A count that is also a door: rendered as a link when it opens another page
 * (the overview → the filtered workbench) or as a toggle button when it
 * filters the list it sits above.
 */
const {
  tone,
  label,
  count,
  href = null,
  active = false,
} = defineProps<{
  tone: Tone;
  label: string;
  count: number;
  href?: string | null;
  active?: boolean;
}>();

const emit = defineEmits<{ click: [] }>();

const dot = computed(() => TONES[tone].dot);
const classes = computed(() => [
  "inline-flex items-center gap-1.5 rounded-full border py-[3px] pr-2.5 pl-2 text-xs tabular-nums transition-colors",
  active
    ? "border-primary/60 bg-primary/10 text-foreground"
    : "border-border bg-background text-foreground hover:bg-accent",
]);
</script>

<template>
  <LiveLink v-if="href" :to="href" :class="classes">
    <span :class="['size-[7px] shrink-0 rounded-full', dot]" aria-hidden="true" />
    <span class="text-muted-foreground">{{ label }}</span>
    <span class="font-medium">{{ count }}</span>
  </LiveLink>
  <button v-else type="button" :class="classes" :aria-pressed="active" @click="emit('click')">
    <span :class="['size-[7px] shrink-0 rounded-full', dot]" aria-hidden="true" />
    <span class="text-muted-foreground">{{ label }}</span>
    <span class="font-medium">{{ count }}</span>
  </button>
</template>
