<script setup lang="ts">
import { computed } from "vue";

const {
  flagCode = null,
  shortLabel,
  size = "md",
  dimmed = false,
} = defineProps<{
  flagCode?: string | null;
  shortLabel: string;
  size?: "sm" | "md" | "lg";
  dimmed?: boolean;
}>();

const normalizedFlagCode = computed(() => {
  if (!flagCode || !/^[a-z]{2}(?:-[a-z]{2,3})?$/i.test(flagCode)) return null;
  return flagCode.toLowerCase();
});

const sizeClass = computed(() => {
  if (size === "sm") return "size-4 text-[0.55rem]";
  if (size === "lg") return "size-7 text-[0.72rem]";
  return "size-5 text-[0.62rem]";
});
</script>

<template>
  <span
    aria-hidden="true"
    :class="[
      'storyarn-language-flag relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full border border-black/10 bg-muted font-bold uppercase leading-none tracking-wide shadow-sm dark:border-white/10',
      sizeClass,
      dimmed && 'opacity-75',
    ]"
  >
    <span class="storyarn-language-flag-label">{{ shortLabel }}</span>
    <span
      v-if="normalizedFlagCode"
      :class="['fi fis absolute inset-0 size-full', `fi-${normalizedFlagCode}`]"
    />
  </span>
</template>
