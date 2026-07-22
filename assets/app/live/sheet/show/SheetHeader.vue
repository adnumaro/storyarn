<script setup lang="ts">
import SheetHealthStatus from "@modules/sheets/components/chrome/header/SheetHealthStatus.vue";
import type { SheetHealth } from "@modules/sheets/types";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: SheetHealth;
}>();
</script>

<template>
  <div class="flex h-8 items-stretch gap-2">
    <SheetHealthStatus :health="health" />
  </div>
</template>
