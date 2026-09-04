<script setup lang="ts">
/**
 * Page frame of the settings grammar: one title, an optional right-aligned
 * slot (save indicator or one action) and the sections below.
 */
const { title } = defineProps<{ title: string }>();
</script>

<template>
  <div class="flex flex-col gap-8">
    <div class="flex items-center gap-3">
      <div class="min-w-0 flex-1">
        <slot name="eyebrow" />
        <h1 class="text-2xl font-semibold leading-tight tracking-[-0.01em]">{{ title }}</h1>
      </div>
      <slot name="actions" />
    </div>

    <slot />
  </div>
</template>
