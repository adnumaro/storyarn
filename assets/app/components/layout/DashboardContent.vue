<script setup lang="ts">
import { LucideProps } from "lucide-vue-next";
import { FunctionalComponent } from "vue";

defineProps<{
  isEmpty?: boolean;
  title?: string;
  subtitle?: string;
  loading?: boolean;
  emptyMessage?: string;
  emptyIcon?: FunctionalComponent<LucideProps, {}, any, {}>;
}>();
</script>

<template>
  <div class="max-w-5xl mx-auto pt-2 pb-8 space-y-6 h-full">
    <div v-if="title">
      <h1 class="text-lg font-semibold">{{ title }}</h1>
      <p v-if="subtitle" class="text-sm text-muted-foreground">{{ subtitle }}</p>
    </div>

    <!-- Empty state -->
    <div
      v-if="isEmpty && emptyMessage"
      class="flex flex-col items-center justify-center py-16 text-center"
    >
      <component v-if="!!emptyIcon" :is="emptyIcon" class="size-12 text-muted-foreground/30 mb-4" />
      <p class="text-sm text-muted-foreground">
        {{ emptyMessage }}
      </p>
    </div>

    <!-- Loading skeleton -->
    <div v-else-if="loading" class="flex justify-center py-12">
      <div
        class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
      />
    </div>

    <template v-else>
      <slot />
    </template>
  </div>
</template>

<style scoped></style>
