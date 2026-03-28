<script setup>
import { BookOpen } from "lucide-vue-next";

const props = defineProps({
  guideBody: { type: String, default: null },
  translations: { type: Object, required: true },
});
</script>

<template>
  <div v-if="guideBody" class="docs-content prose prose-sm dark:prose-invert max-w-none" v-html="guideBody" />

  <div v-else class="text-center py-20">
    <BookOpen class="size-12 text-muted-foreground/30 mx-auto mb-4" />
    <p class="text-muted-foreground/50">{{ translations.noDocsAvailable }}</p>
  </div>
</template>
