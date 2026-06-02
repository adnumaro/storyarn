<script setup lang="ts">
const { width = 1000, height = 1000 } = defineProps<{
  width?: number;
  height?: number;
}>();
</script>

<template>
  <div class="space-y-0.5">
    <label class="text-xs font-medium text-muted-foreground">{{
      $t("scenes.settings.dimensions")
    }}</label>
    <p class="text-xs text-muted-foreground/70">
      {{ width || 1000 }} &times; {{ height || 1000 }} px
    </p>
  </div>
</template>
