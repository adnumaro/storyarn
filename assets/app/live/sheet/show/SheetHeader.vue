<script setup lang="ts">
import SheetCommentsHeaderControls from "@modules/sheets/components/chrome/header/SheetCommentsHeaderControls.vue";
import SheetHealthStatus from "@modules/sheets/components/chrome/header/SheetHealthStatus.vue";
import type { SheetHealth } from "@modules/sheets/types";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
  comments = null,
} = defineProps<{
  health?: SheetHealth;
  comments?: {
    count: number;
    open: boolean;
    placing?: boolean;
    canComment?: boolean;
  } | null;
}>();
</script>

<template>
  <div class="flex h-8 items-stretch gap-2">
    <SheetHealthStatus :health="health" />
    <SheetCommentsHeaderControls
      :count="comments?.count ?? 0"
      :open="comments?.open ?? false"
      :placing="comments?.placing ?? false"
      :can-comment="comments?.canComment ?? false"
    />
  </div>
</template>
