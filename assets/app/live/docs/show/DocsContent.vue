<script setup lang="ts">
import { BookOpen } from "lucide-vue-next";

const { guideBody = null } = defineProps<{
  guideBody?: string | null;
}>();
</script>

<template>
  <div
    v-if="guideBody"
    class="docs-content max-w-none"
    v-html="guideBody"
  />

  <div v-else class="text-center py-20">
    <BookOpen class="size-12 text-muted-foreground/30 mx-auto mb-4" />
    <p class="text-muted-foreground/50">{{ $t("common.docs.no_docs") }}</p>
  </div>
</template>
