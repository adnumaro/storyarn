<script setup lang="ts">
import type { LucideProps } from "lucide-vue-next";
import type { FunctionalComponent } from "vue";

const { isEmpty, title, subtitle, loading, emptyMessage, emptyIcon, icon } = defineProps<{
  isEmpty?: boolean;
  title?: string;
  subtitle?: string;
  loading?: boolean;
  emptyMessage?: string;
  emptyIcon?: FunctionalComponent<LucideProps>;
  icon?: FunctionalComponent<LucideProps>;
}>();
</script>

<template>
  <div
    data-testid="dashboard-content"
    class="relative isolate mx-auto h-full w-full max-w-7xl space-y-6 pb-10 pt-1"
  >
    <div aria-hidden="true" class="pointer-events-none absolute inset-x-0 -top-6 -z-10 h-52">
      <div
        class="absolute left-[8%] top-0 size-44 rounded-full bg-primary/[0.055] blur-3xl dark:bg-primary/[0.075]"
      />
      <div
        class="absolute right-[12%] top-8 size-36 rounded-full bg-project-accent/[0.045] blur-3xl dark:bg-project-accent/[0.06]"
      />
    </div>

    <header v-if="title" class="relative flex items-start gap-3.5 pb-1">
      <span
        v-if="icon"
        class="mt-0.5 grid size-11 shrink-0 place-items-center rounded-2xl border border-primary/20 bg-primary/[0.09] text-primary shadow-sm"
      >
        <component :is="icon" class="size-5" aria-hidden="true" />
      </span>
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">{{ title }}</h1>
        <p v-if="subtitle" class="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">
          {{ subtitle }}
        </p>
      </div>
    </header>

    <!-- Empty state -->
    <div
      v-if="isEmpty && emptyMessage"
      class="relative flex min-h-80 flex-col items-center justify-center overflow-hidden rounded-3xl border border-dashed border-border bg-card/60 px-6 py-16 text-center shadow-sm"
    >
      <div
        aria-hidden="true"
        class="absolute -top-16 size-56 rounded-full bg-primary/[0.07] blur-3xl"
      />
      <span
        v-if="emptyIcon"
        class="relative mb-5 grid size-16 place-items-center rounded-2xl border border-primary/15 bg-primary/[0.08] text-primary"
      >
        <component :is="emptyIcon" class="size-7" />
      </span>
      <p class="relative max-w-md text-sm leading-6 text-muted-foreground">
        {{ emptyMessage }}
      </p>
    </div>

    <!-- Loading skeleton -->
    <div v-else-if="loading" class="space-y-6" aria-busy="true">
      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <div
          v-for="index in 4"
          :key="index"
          class="h-32 animate-pulse rounded-2xl border border-border/60 bg-card/70"
        />
      </div>
      <div class="h-72 animate-pulse rounded-2xl border border-border/60 bg-card/70" />
    </div>

    <div v-else class="relative space-y-6">
      <slot />
    </div>
  </div>
</template>
