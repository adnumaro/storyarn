<script setup lang="ts">
import type { LucideProps } from "@lucide/vue";
import type { FunctionalComponent } from "vue";

const { isEmpty, title, subtitle, loading, loadingLabel, failure, emptyMessage, emptyIcon } =
  defineProps<{
    isEmpty?: boolean;
    title?: string;
    subtitle?: string;
    loading?: boolean;
    loadingLabel?: string;
    failure?: {
      kind: "error" | "stale";
      message: string;
      retryLabel?: string;
    };
    emptyMessage?: string;
    emptyIcon?: FunctionalComponent<LucideProps, {}, any, {}>;
  }>();

const emit = defineEmits<{
  retry: [];
}>();
</script>

<template>
  <div class="max-w-5xl mx-auto pt-2 pb-8 space-y-6 h-full">
    <div v-if="title">
      <h1 class="text-lg font-semibold">{{ title }}</h1>
      <p v-if="subtitle" class="text-sm text-muted-foreground">{{ subtitle }}</p>
    </div>

    <!-- Error state -->
    <div
      v-if="failure?.kind === 'error'"
      data-testid="dashboard-overview-error"
      class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-10 text-center"
      role="alert"
    >
      <p class="text-sm text-destructive">
        {{ failure.message }}
      </p>
      <button
        v-if="failure.retryLabel"
        type="button"
        data-testid="dashboard-overview-retry"
        class="inline-flex h-8 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        @click="emit('retry')"
      >
        {{ failure.retryLabel }}
      </button>
    </div>

    <template v-else>
      <div
        v-if="failure?.kind === 'stale'"
        data-testid="dashboard-overview-stale"
        class="mb-4 flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
        role="status"
        aria-live="polite"
      >
        <p class="text-sm text-amber-700 dark:text-amber-300">{{ failure.message }}</p>
        <button
          v-if="failure.retryLabel"
          type="button"
          data-testid="dashboard-overview-stale-retry"
          class="inline-flex h-8 shrink-0 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
          @click="emit('retry')"
        >
          {{ failure.retryLabel }}
        </button>
      </div>

      <!-- Empty state -->
      <div
        v-if="isEmpty && emptyMessage"
        class="flex flex-col items-center justify-center py-16 text-center"
      >
        <component
          v-if="!!emptyIcon"
          :is="emptyIcon"
          class="size-12 text-muted-foreground/30 mb-4"
        />
        <p class="text-sm text-muted-foreground">
          {{ emptyMessage }}
        </p>
      </div>

      <!-- Loading skeleton -->
      <div
        v-else-if="loading"
        data-testid="dashboard-overview-loading"
        class="flex justify-center py-12"
        role="status"
        aria-live="polite"
      >
        <div
          class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
          aria-hidden="true"
        />
        <span v-if="loadingLabel" class="sr-only">{{ loadingLabel }}</span>
      </div>

      <template v-else>
        <slot />
      </template>
    </template>

    <slot name="supplementary" />
  </div>
</template>

<style scoped></style>
