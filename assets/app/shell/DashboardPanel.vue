<script setup lang="ts">
import type { Component } from "vue";

const {
  title,
  subtitle = null,
  icon = null,
  padded = true,
  testId = null,
} = defineProps<{
  title: string;
  subtitle?: string | null;
  icon?: Component | null;
  padded?: boolean;
  testId?: string | null;
}>();
</script>

<template>
  <section
    :data-testid="testId || undefined"
    class="overflow-hidden rounded-2xl border border-border/70 bg-card/80 shadow-[0_1px_2px_rgba(0,0,0,0.04)] backdrop-blur-sm"
  >
    <header
      class="flex min-h-16 items-center justify-between gap-4 border-b border-border/60 bg-linear-to-r from-muted/55 via-card/20 to-primary/[0.035] px-4 py-3.5 sm:px-5"
    >
      <div class="flex min-w-0 items-center gap-3">
        <span
          v-if="icon"
          class="grid size-9 shrink-0 place-items-center rounded-xl border border-primary/15 bg-primary/[0.08] text-primary"
        >
          <component :is="icon" class="size-4.5" aria-hidden="true" />
        </span>
        <div class="min-w-0">
          <h2 class="truncate text-sm font-semibold tracking-tight text-foreground">
            {{ title }}
          </h2>
          <p v-if="subtitle" class="mt-0.5 truncate text-xs text-muted-foreground">
            {{ subtitle }}
          </p>
        </div>
      </div>
      <slot name="actions" />
    </header>

    <div :class="padded ? 'p-4 sm:p-5' : ''">
      <slot />
    </div>

    <div v-if="$slots.footer" class="border-t border-border/60 bg-muted/20 px-4 py-3 sm:px-5">
      <slot name="footer" />
    </div>
  </section>
</template>
