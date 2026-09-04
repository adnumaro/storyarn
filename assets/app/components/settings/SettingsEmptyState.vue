<script setup lang="ts">
import type { Component } from "vue";

/** Centered empty state inside a section card: icon, one line, optional text. */
const {
  icon,
  title,
  text = null,
} = defineProps<{
  icon: Component;
  title: string;
  text?: string | null;
}>();
</script>

<template>
  <div class="flex flex-col items-center gap-1.5 px-4 py-8 text-center">
    <component :is="icon" class="size-[22px] text-muted-foreground" />
    <div class="mt-1.5 font-medium">{{ title }}</div>
    <p v-if="text" class="max-w-[380px] text-[13px] text-muted-foreground text-pretty">
      {{ text }}
    </p>
    <div v-if="$slots.default" class="mt-2.5">
      <slot />
    </div>
  </div>
</template>
